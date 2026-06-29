# frozen_string_literal: true

module Coder
  # SweepExpiredLocksJob — manual-invocation housekeeping for expired Coder
  # workspace locks. The scheduled path is
  # `Workflows::CoderSweepExpiredLocksWorkflow`
  # (`app/temporal/schedules.yml`, hourly cron) which runs the same logic via
  # `Activities::Coder::SweepExpiredLocksActivity`. This job stays as a
  # `perform_now` entry-point for Rails console / one-off backfills.
  #
  # Correctness does not depend on this job (DD-7) — the atomic acquire SQL
  # in `Coder::LockService` reclaims expired rows on the fly via
  # `ON CONFLICT … WHERE expires_at <= EXCLUDED.created_at`. Sweeping just
  # keeps the table tidy.
  class SweepExpiredLocksJob < ApplicationJob
    queue_as :low

    def perform
      deleted = IntegrationData
                  .with_key_prefix(Coder::LockService::LOCK_KEY_PREFIX)
                  .expired
                  .delete_all
      Rails.logger.info("[Coder::SweepExpiredLocksJob] swept #{deleted} expired lock rows")
      deleted
    end
  end
end
