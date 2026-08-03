# frozen_string_literal: true

module Workflows
  # SkillsDemandSyncWorkflow — daily, demand-seeded refresh of the skills catalog.
  # Wired into `app/temporal/schedules.yml`.
  #
  # The weekly full sweep follows a static seed list of topics someone guessed at.
  # This one follows the terms users actually searched for (CatalogSearchQuery), which
  # is the better signal for which slice of a 600k-skill registry is worth mirroring:
  # people search for what they are about to install.
  #
  # A separate workflow rather than an input flag on the weekly one, because
  # `schedules.yml` passes no input to static schedules — adding that would mean
  # changing a seam every scheduled workflow in the app depends on, for one feature.
  #
  # Daily is affordable precisely because it is narrow: a few dozen search terms plus
  # the same bounded backfill and audit passes, not the ~110-request full sweep.
  class SkillsDemandSyncWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.skills_sync_catalog_activity, { "mode" => "demand" },
        start_to_close_timeout: 1_800,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
