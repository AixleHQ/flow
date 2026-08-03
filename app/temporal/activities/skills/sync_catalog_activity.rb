# frozen_string_literal: true

# Activities::Skills::SyncCatalogActivity
# Refreshes the mirrored skills.sh catalog. Driven by
# `Workflows::SkillsCatalogSyncWorkflow` on a weekly Temporal schedule.
#
# Correctness does not depend on the cadence: the sweep upserts on natural keys
# and recomputes ranking wholesale, so a missed run, a double run, or a schedule
# lost to a worker redeploy all converge on the next execution. A stale mirror
# degrades the default browse view only — typed searches go upstream live, and
# installing a skill re-fetches it, so nothing breaks.

module Activities
  module Skills
    class SyncCatalogActivity < ::Activities::Base
      def run(_input = nil)
        result = ::Skills::CatalogSync.call

        log(:info, "skills catalog sync #{result}")
        # Every counter the Result carries: workflow history is the only durable
        # record of a weekly run, so a dropped counter makes that coverage
        # unobservable after the fact.
        {
          fetched: result.fetched,
          upserted: result.upserted,
          failed: result.failed,
          backfilled: result.backfilled,
          audited: result.audited
        }
      end
    end
  end
end
