# frozen_string_literal: true

module Workflows
  # Hourly usage rollup (see app/temporal/schedules.yml), and the same rollup
  # over a longer range when an admin recomputes history from the tenant report.
  #
  # Retried, unlike capacity metering: it rewrites only its own rows from the
  # database, so a second attempt writes the same answer and bills nobody.
  class UsageRollupWorkflow < Base
    def run(input = nil)
      execute_activity(
        activities.usage_rollup_hours_activity,
        { from_hour: input&.from_hour, to_hour: input&.to_hour }.compact,
        start_to_close_timeout: 1800,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 3)
      )
    end
  end
end
