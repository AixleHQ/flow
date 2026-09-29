# frozen_string_literal: true

module Workflows
  class ToolResultCleanupWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.tool_results_cleanup_activity, {},
        start_to_close_timeout: 600,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
