# frozen_string_literal: true

module Workflows
  # MCPConnectorCatalogSyncWorkflow — weekly refresh of the mirrored MCP
  # connector catalog. Wired into `app/temporal/schedules.yml`.
  #
  # Weekly. The MCP Registry suggests hourly for aggregators, but only discovery
  # goes stale here — an install re-fetches its manifest live — so the trade is
  # a newly published connector taking up to a week to become searchable, in
  # exchange for a fraction of the outbound traffic against a service that
  # publishes no rate limits and disclaims its own uptime.
  #
  # A long start_to_close timeout because a FIRST run walks the entire registry
  # (~10k servers at 100 per page); steady-state runs are incremental and finish
  # in seconds. Only two attempts: a failed sync leaves the previous mirror
  # intact and the catalog keeps working, so a tight retry loop buys nothing.
  class MCPConnectorCatalogSyncWorkflow < Base
    def run(input = nil)
      execute_activity(
        activities.mcp_sync_connector_catalog_activity, input || {},
        start_to_close_timeout: 1_800,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
