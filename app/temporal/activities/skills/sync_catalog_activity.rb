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
      # Two cadences, one activity:
      #   full   — weekly, the static topic + owner seeds (broad coverage)
      #   demand — daily, the terms users actually searched for (what they are about
      #            to install), plus the same bounded backfill and audit passes
      def run(input = nil)
        mode = input.is_a?(Hash) ? (input["mode"] || input[:mode]).to_s : "full"
        result = mode == "demand" ? ::Skills::CatalogSync.demand : ::Skills::CatalogSync.call

        log(:info, "skills catalog sync (#{mode}) #{result}")
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
