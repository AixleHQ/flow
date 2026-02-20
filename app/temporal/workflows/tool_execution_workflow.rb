# frozen_string_literal: true

module Workflows
  class ToolExecutionWorkflow < Base
    TOOL_DEFAULT_TIMEOUT = 300
    TOOL_MAX_TIMEOUT = 1800
    IMAGE_PULL_TIMEOUT = 600
    CLEANUP_TIMEOUT = 60

    def run(input)
      tool_id = input.tool_id
      timeout = input.timeout || TOOL_DEFAULT_TIMEOUT

      Temporalio::Workflow.logger.info("[ToolWorkflow] Starting tool #{tool_id}")

      execute_activity(
        activities.tool_pull_image_activity,
        { tool_id: tool_id },
        start_to_close_timeout: IMAGE_PULL_TIMEOUT
      )

      execution_timeout = [timeout.to_i, TOOL_MAX_TIMEOUT].min + 300
      result = execute_activity(
        activities.tool_execute_container_activity,
        { tool_id: tool_id, parameters: input.parameters, project_id: input.project_id, timeout: timeout },
        start_to_close_timeout: execution_timeout
      )

      container_id = result[:container_id] || result["container_id"]

      if container_id.present?
        begin
          execute_activity(
            activities.tool_cleanup_container_activity,
            { container_id: container_id },
            start_to_close_timeout: CLEANUP_TIMEOUT,
            retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2, initial_interval: 5)
          )
        rescue StandardError => e
          Temporalio::Workflow.logger.error("[ToolWorkflow] Cleanup failed: #{e.message}")
        end
      end

      result
    end

    private

    def activities
      @activities ||= WorkflowService.tool_execution_workflow.activities
    end
  end
end
