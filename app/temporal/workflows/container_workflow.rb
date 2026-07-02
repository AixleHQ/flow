# frozen_string_literal: true

module Workflows
  # ContainerWorkflow
  # Generic workflow for all container types (agent auth, agent session, tool execution).
  #
  # Flow: execute_phases → cleanup (always) → on_failure (if error) → raise
  #
  # Strategy decides what on_failure means (e.g. ToolStrategy marks ToolResult as failed).
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
      @input = input
      @manifest = input.manifest || {}
      @state = {}

      execution_error = execute_phases
      cleanup_error = run_cleanup(execution_error)
      handle_failure(execution_error, cleanup_error)

      @state
    rescue Temporalio::Error => e
      raise unless Temporalio::Error.canceled?(e)

      run_cleanup_detached("Workflow cancelled")
      raise
    end

    private

    # --- High-level steps ---

    def execute_phases
      EXECUTION_PHASES.each do |phase|
        config = phase_config(phase)
        @state = run_phase(phase, timeout: config_timeout(config))
        await_signal_if_needed(config)
      end
      nil
    rescue Temporalio::Error::ActivityError => e
      extract_error_message(e)
    end

    def run_cleanup(execution_error)
      run_phase("cleanup",
        error: execution_error,
        timeout: config_timeout(phase_config("cleanup"), 120),
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2, initial_interval: 5))
      nil
    rescue Temporalio::Error::ActivityError => e
      extract_error_message(e)
    end

    def run_cleanup_detached(error_message)
      config = phase_config("cleanup")
      execute_activity(
        activities.container_phase_activity,
        { phase: "cleanup", state: @state, error: error_message, **passthrough_fields },
        start_to_close_timeout: config_timeout(config, 120),
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2, initial_interval: 5),
        cancellation: Temporalio::Cancellation.new
      )
    rescue StandardError => e
      Temporalio::Workflow.logger.error("[ContainerWorkflow] Cleanup on cancel failed: #{e.message}")
    end

    def handle_failure(execution_error, cleanup_error)
      return unless execution_error

      final_error = cleanup_error \
        ? "Execution failed: #{execution_error}; Cleanup also failed: #{cleanup_error}"
        : execution_error

      run_on_failure(final_error)

      raise Temporalio::Error::ApplicationError.new(
        final_error,
        type: cleanup_error ? "ContainerWorkflowError" : "ContainerExecutionError",
        non_retryable: true
      )
    end

    def run_on_failure(error_message)
      run_phase("on_failure",
        error: error_message,
        timeout: 30,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2, initial_interval: 2))
    rescue Temporalio::Error::ActivityError => e
      Temporalio::Workflow.logger.error("[ContainerWorkflow] on_failure failed: #{extract_error_message(e)}")
    end

    # --- Activity execution ---

    def run_phase(phase, error: nil, timeout: 300, retry_policy: nil)
      kwargs = { start_to_close_timeout: timeout }
      kwargs[:retry_policy] = retry_policy if retry_policy
      # Only tool executions heartbeat during exec (ToolStrategy waits for the
      # container in heartbeat slices, which is also what makes cancellation
      # deliverable). Agent-session exec phases are quick and don't heartbeat,
      # and a heartbeat timeout on a non-heartbeating activity would kill
      # healthy work — so scope it to tool runs.
      kwargs[:heartbeat_timeout] = 60 if phase.to_s == "exec" && tool_execution?

      execute_activity(
        activities.container_phase_activity,
        { phase: phase, state: @state, error: error, **passthrough_fields },
        **kwargs
      )
    end

    # --- Signal handling ---

    def await_signal_if_needed(config)
      return unless config.respond_to?(:[])

      signal_name = config[:await_signal] || config["await_signal"]
      return unless signal_name
      return if @state.is_a?(Hash) && (@state[:agent_completed] || @state["agent_completed"])

      timeout = (config[:signal_timeout] || config["signal_timeout"])&.to_i || 82_800

      Temporalio::Workflow.timeout(timeout) do
        Temporalio::Workflow.wait_condition { @finished }
      rescue Timeout::Error
        nil
      end
    end

    # --- Helpers ---

    def tool_execution?
      @input.respond_to?(:tool_id) && @input.tool_id
    end

    def phase_config(phase)
      return {} unless @manifest.respond_to?(:[])
      @manifest[phase] || @manifest[phase.to_s] || @manifest[phase.to_sym] || {}
    end

    def config_timeout(config, default = 300)
      return default unless config.respond_to?(:[])
      (config[:timeout] || config["timeout"])&.to_i || default
    end

    def passthrough_fields
      result = {}
      %i[session_id tool_id tool_result_id parameters project_id timeout].each do |field|
        result[field] = @input.send(field) if @input.respond_to?(field) && @input.send(field)
      end
      result
    end
  end
end
