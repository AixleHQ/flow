# frozen_string_literal: true

module Workflows
  # MCPToolDriftScanWorkflow — daily re-probe of catalog-installed MCP servers,
  # looking for tools whose declarations changed after they were approved.
  # Wired into `app/temporal/schedules.yml`.
  #
  # Daily rather than hourly: a rug pull is a durable change, not a transient
  # one, and each scan makes an outbound request per installed server. The
  # protocol's `2026-07-28` revision added `ttlMs` freshness hints that could
  # drive a smarter cadence later; a fixed daily sweep is the honest starting
  # point.
  #
  # Two attempts only. A server that is down today will be re-probed tomorrow,
  # and hammering an unreachable third party achieves nothing.
  class MCPToolDriftScanWorkflow < Base
    def run(input = nil)
      execute_activity(
        activities.mcp_scan_tool_drift_activity, input || {},
        start_to_close_timeout: 1_800,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
