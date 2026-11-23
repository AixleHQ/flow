# frozen_string_literal: true

module Workflows
  class SuspendedSessionExpiryWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.session_expire_suspended_activity, {},
        start_to_close_timeout: 1800,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
