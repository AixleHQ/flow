# frozen_string_literal: true

# Activities::Coder::SweepExpiredLocksActivity
# Deletes expired Coder workspace lock rows from `integration_data`. Driven by
# `Workflows::CoderSweepExpiredLocksWorkflow` on an hourly Temporal schedule.
#
# Correctness does not depend on this activity (DD-7): the atomic acquire SQL
# in `Coder::LockService` already reclaims expired rows on the fly via
# `ON CONFLICT … WHERE expires_at <= EXCLUDED.created_at`. This is purely
# table-tidy housekeeping.

module Activities
  module Coder
    class SweepExpiredLocksActivity < ::Activities::Base
      def run(_input = nil)
        deleted = IntegrationData
                    .with_key_prefix(::Coder::LockService::LOCK_KEY_PREFIX)
                    .expired
                    .delete_all

        log(:info, "swept #{deleted} expired Coder lock rows")
        { deleted: deleted }
      end
    end
  end
end
