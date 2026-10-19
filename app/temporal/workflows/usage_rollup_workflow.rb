# frozen_string_literal: true

module Workflows
  # Hourly usage rollup (see app/temporal/schedules.yml). Started by hand with a
  # `from_hour` (and optionally a `to_hour`), it measures that range again, which
  # is how history is rebuilt after a fix to the rollup.
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
