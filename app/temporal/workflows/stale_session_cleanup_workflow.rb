# frozen_string_literal: true

# Stale Session Cleanup Workflow
# Scheduled workflow that runs periodically to clean up terminal sessions
# stuck in active states after their Temporal workflows have ended.
#
# Runs as a Temporal schedule (see schedules.yml).

module Workflows
  class StaleSessionCleanupWorkflow < Base
    ACTIVITY_TIMEOUT = 300 # 5 minutes

    def run(_input = nil)
      execute_activity(
        activities.session_cleanup_stale_activity,
        {},
        start_to_close_timeout: ACTIVITY_TIMEOUT,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end

    private

    def activities
      @activities ||= WorkflowService.stale_session_cleanup_workflow.activities
    end
  end
end
