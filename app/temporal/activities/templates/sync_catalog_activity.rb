# frozen_string_literal: true

# Activities::Templates::SyncCatalogActivity
# Mirrors the public templates repository. Driven by
# `Workflows::TemplatesCatalogSyncWorkflow` on an hourly Temporal schedule.
#
# A run at an already-mirrored commit is two cheap requests and no writes, so
# the cadence is about how soon a merged template appears, not about load.
module Activities
  module Templates
    class SyncCatalogActivity < ::Activities::Base
      def run(_input = nil)
        result = ::Templates::CatalogSync.call

        log(:info, "templates catalog sync #{result}")
        result.skipped.each { |skip| log(:warn, "templates catalog skipped #{skip[:identifier]}: #{skip[:reason]}") }
        {
          commit_sha: result.commit_sha,
          upserted: result.upserted,
          skipped: result.skipped.pluck(:identifier),
          revoked: result.revoked,
          unchanged: result.unchanged
        }
      end
    end
  end
end
