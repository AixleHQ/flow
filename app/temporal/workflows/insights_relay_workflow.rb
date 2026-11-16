# frozen_string_literal: true

module Workflows
  # The sender of the Insights relay (docs/design/insights-otlp-relay.md §5): what the
  # ingest wrote to the outbox reaches Insights within a minute, merged per connection.
  class InsightsRelayWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.insights_relay_drain_activity, {},
        start_to_close_timeout: 600,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 3)
      )
    end
  end
end
