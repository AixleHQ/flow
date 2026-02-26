# frozen_string_literal: true

module Workflows
  # ContainerWorkflow
  # Generic workflow for all container types (agent auth, agent session, tool execution).
  #
  # Manifest (phase configs) is passed as workflow input — no need for a separate
  # activity since phase_config is a pure function of strategy type + input.
  #
  # For each phase the workflow:
  #   1. Executes the ContainerPhaseActivity with phase-specific timeout
  #   2. If phase config has await_signal — waits for the signal with signal_timeout
  #
  # Cleanup always runs (even on failure), with optional retry policy.
  #
  # Error handling:
  #   - ActivityError from failed phases: caught, stored, passed to cleanup
  #   - Cleanup errors: caught, logged, surfaced in result (not swallowed)
  #   - Non-Temporal errors (bugs): NOT caught — cause Workflow Task Failure → auto-retry
  #
  # IMPORTANT: Workflow code runs inside Temporal sandbox — no autoloading,
  # no ActiveSupport, no Thread::Mutex. Keep it plain Ruby.
  #
  class ContainerWorkflow < Base
    EXECUTION_PHASES = %w[pull_image create_container start_container exec].freeze

    workflow_signal
    def container_finished
      @finished = true
    end

    def run(input)
      @finished = false
      manifest = input.manifest || {}
      state = {}
      execution_error = nil

      Temporalio::Workflow.logger.info("[ContainerWorkflow] Starting")

      begin
        EXECUTION_PHASES.each do |phase|
          config = phase_config(manifest, phase)

          state = execute_activity(
            phase_activity,
            { phase: phase, state: state, **passthrough_input(input) },
            start_to_close_timeout: config_timeout(config)
          )

          await_signal_if_needed(config, state)
        end
      rescue Temporalio::Error::ActivityError => e
        Temporalio::Workflow.logger.error("[ContainerWorkflow] Phase failed: #{e.message}")
        execution_error = extract_error_message(e)
      end

      cleanup_error = run_cleanup(input, state, execution_error, manifest)

      if execution_error && cleanup_error
        raise Temporalio::Error::ApplicationError.new(
          "Execution failed: #{execution_error}; Cleanup also failed: #{cleanup_error}",
          type: "ContainerWorkflowError",
          non_retryable: true
        )
      elsif execution_error
        raise Temporalio::Error::ApplicationError.new(
          execution_error,
          type: "ContainerExecutionError",
          non_retryable: true
        )
      end

      state
    end

    private

    # @return [String, nil] cleanup error message, or nil on success
    def run_cleanup(input, state, execution_error, manifest)
      config = phase_config(manifest, "cleanup")

      execute_activity(
        phase_activity,
        { phase: "cleanup", state: state, error: execution_error, **passthrough_input(input) },
        start_to_close_timeout: config_timeout(config, 120),
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2, initial_interval: 5)
      )
      nil
    rescue Temporalio::Error::ActivityError => e
      msg = extract_error_message(e)
      Temporalio::Workflow.logger.error("[ContainerWorkflow] Cleanup failed: #{msg}")
      msg
    end

    def extract_error_message(activity_error)
      cause = activity_error.cause
      cause ? cause.message : activity_error.message
    end

    def await_signal_if_needed(config, state)
      return unless config.respond_to?(:[])

      signal_name = config[:await_signal] || config["await_signal"]
      return unless signal_name

      completed = state.is_a?(Hash) && (state[:agent_completed] || state["agent_completed"])
      return if completed

      timeout = config[:signal_timeout] || config["signal_timeout"]
      timeout = timeout ? timeout.to_i : 82_800

      Temporalio::Workflow.logger.info("[ContainerWorkflow] Waiting for signal: #{signal_name}")
      Temporalio::Workflow.timeout(timeout) do
        Temporalio::Workflow.wait_condition { @finished }
      rescue Timeout::Error
        Temporalio::Workflow.logger.info("[ContainerWorkflow] Signal wait timed out after #{timeout}s")
      end
    end

    def phase_config(manifest, phase)
      return {} unless manifest.respond_to?(:[])

      manifest[phase] || manifest[phase.to_s] || manifest[phase.to_sym] || {}
    end

    def config_timeout(config, default = 300)
      return default unless config.respond_to?(:[])

      val = config[:timeout] || config["timeout"]
      val ? val.to_i : default
    end

    def phase_activity
      @phase_activity ||= WorkflowService.container_workflow.activities.container_phase_activity
    end

    def passthrough_input(input)
      result = {}
      result[:session_id] = input.session_id if input.respond_to?(:session_id) && input.session_id
      result[:tool_id] = input.tool_id if input.respond_to?(:tool_id) && input.tool_id
      result[:tool_result_id] = input.tool_result_id if input.respond_to?(:tool_result_id) && input.tool_result_id
      result[:parameters] = input.parameters if input.respond_to?(:parameters) && input.parameters
      result[:project_id] = input.project_id if input.respond_to?(:project_id) && input.project_id
      result[:timeout] = input.timeout if input.respond_to?(:timeout) && input.timeout
      result
    end
  end
end
