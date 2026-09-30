# frozen_string_literal: true

module Workflows
  class TrackerSubscriptionRefreshWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.trackers_refresh_subscriptions_activity, {},
        start_to_close_timeout: 600,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
