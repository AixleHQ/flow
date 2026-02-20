# frozen_string_literal: true

module Workflows
  class AgentContainerWorkflow < Base
    AGENT_PHASES_TIMEOUT = 300       # 5 minutes for interactive phases
    NON_INTERACTIVE_TIMEOUT = 85_800 # 23h50m for non-interactive exec
    IMAGE_PULL_TIMEOUT = 600         # 10 minutes
    CLEANUP_TIMEOUT = 120            # 2 minutes (includes artifact collection)
    AGENT_SIGNAL_TIMEOUT = 82_800    # 23 hours

    workflow_signal
    def container_finished
      @finished = true
    end

    def run(input)
      @finished = false
      session_id = input.session_id || input["session_id"]

      Temporalio::Workflow.logger.info("[AgentWorkflow] Starting session #{session_id}")

      execute_activity(
        activities.agent_pull_image_activity,
        { session_id: session_id },
        start_to_close_timeout: IMAGE_PULL_TIMEOUT
      )

      result = execute_activity(
        activities.agent_execute_container_activity,
        { session_id: session_id },
        start_to_close_timeout: execution_timeout(input)
      )

      agent_completed = result[:agent_completed] || result["agent_completed"]

      unless agent_completed
        Temporalio::Workflow.logger.info("[AgentWorkflow] Waiting for container_finished signal")
        Temporalio::Workflow.timeout(AGENT_SIGNAL_TIMEOUT) do
          Temporalio::Workflow.wait_condition { @finished }
        rescue Timeout::Error
          Temporalio::Workflow.logger.warn("[AgentWorkflow] Signal timed out, proceeding to cleanup")
        end
      end

      begin
        execute_activity(
          activities.agent_cleanup_container_activity,
          { session_id: session_id },
          start_to_close_timeout: CLEANUP_TIMEOUT,
          retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2, initial_interval: 5)
        )
      rescue StandardError => e
        Temporalio::Workflow.logger.error("[AgentWorkflow] Cleanup failed: #{e.message}")
      end

      result
    end

    private

    def activities
      @activities ||= WorkflowService.agent_container_workflow.activities
    end

    def execution_timeout(input)
      mode = input.mode || input["mode"]
      mode == "non_interactive" ? NON_INTERACTIVE_TIMEOUT : AGENT_PHASES_TIMEOUT
    end
  end
end
