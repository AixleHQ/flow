# frozen_string_literal: true

module Workflows
  # Safety-net relay for the transactional outbox. Runs on a Temporal cron
  # schedule (see app/temporal/schedules.yml) with SKIP-overlap, and drains any
  # trigger events left "pending" by a producer that crashed before dispatching.
  # The happy path dispatches inline; this only catches the stragglers.
  class OutboxRelayWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.outbox_relay_drain_activity, {},
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 3)
      )
    end
  end
end
