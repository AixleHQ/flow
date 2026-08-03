# frozen_string_literal: true

# Activities::MCP::SyncConnectorCatalogActivity
# Refreshes the mirrored MCP connector catalog from the Official MCP Registry.
# Driven by `Workflows::MCPConnectorCatalogSyncWorkflow` on a weekly Temporal
# schedule.
#
# Correctness does not depend on the cadence: MCP::ConnectorCatalogSync resumes
# from the newest mirrored change, so a missed run, a double run, or a schedule
# lost to a worker redeploy all converge on the next execution. A stale mirror
# degrades discovery, never the product — installs and the manual MCP form keep
# working regardless.

module Activities
  module MCP
    class SyncConnectorCatalogActivity < ::Activities::Base
      def run(input = nil)
        full = input.is_a?(Hash) && (input["full"] || input[:full])
        result = ::MCP::ConnectorCatalogSync.call(full: full.present?)

        log(:info, "connector catalog sync #{result}")
        { fetched: result.fetched, upserted: result.upserted, failed: result.failed }
      end
    end
  end
end
