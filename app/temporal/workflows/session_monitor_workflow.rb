# frozen_string_literal: true

module Workflows
  # One pass of Sessions::Monitor over the live sessions' terminals (schedules.yml).
  class SessionMonitorWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.workflow_monitor_sessions_activity, {},
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
