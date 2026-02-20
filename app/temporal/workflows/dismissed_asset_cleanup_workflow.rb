# frozen_string_literal: true

module Workflows
  class DismissedAssetCleanupWorkflow < Base
    ACTIVITY_TIMEOUT = 300

    def run(_input = nil)
      execute_activity(
        activities.asset_cleanup_dismissed_activity,
        {},
        start_to_close_timeout: ACTIVITY_TIMEOUT,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end

    private

    def activities
      @activities ||= WorkflowService.dismissed_asset_cleanup_workflow.activities
    end
  end
end
