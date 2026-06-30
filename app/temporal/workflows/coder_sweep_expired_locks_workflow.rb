# frozen_string_literal: true

module Workflows
  # CoderSweepExpiredLocksWorkflow — hourly housekeeping for expired Coder
  # workspace locks. Wired into `app/temporal/schedules.yml` so the project's
  # existing Temporal cron drives it. Correctness does not depend on the
  # cadence (DD-7) — the atomic acquire SQL in `Coder::LockService` reclaims
  # expired rows on the fly. The schedule just keeps `integration_data` tidy.
  class CoderSweepExpiredLocksWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.coder_sweep_expired_locks_activity, {},
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
