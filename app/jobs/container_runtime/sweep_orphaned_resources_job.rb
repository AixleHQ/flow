# frozen_string_literal: true

module ContainerRuntime
  # SweepOrphanedResourcesJob — manual-invocation entry point for the runtime
  # garbage collector, for a Rails console during an incident ("reclaim the
  # leftovers now" rather than waiting out the cron interval).
  #
  # The scheduled path is `Workflows::ContainerSweepOrphanedResourcesWorkflow`
  # (`app/temporal/schedules.yml`). This job runs the same activity rather than
  # a second copy of the reconciliation, so the safety guards documented in
  # `Activities::Container::SweepOrphanedResourcesActivity` — provable owner,
  # dead owner, minimum age — can never drift between the two entry points.
  class SweepOrphanedResourcesJob < ApplicationJob
    queue_as :low

    def perform
      summary = Activities::Container::SweepOrphanedResourcesActivity.new.run
      Rails.logger.info("[ContainerRuntime::SweepOrphanedResourcesJob] #{summary}")
      summary
    end
  end
end
