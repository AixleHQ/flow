# frozen_string_literal: true

# Activities::MCP::ScanToolDriftActivity
# Re-probes catalog-installed MCP servers and records any change to the tools
# they declare. Driven by `Workflows::MCPToolDriftScanWorkflow` on a daily
# Temporal schedule.
#
# This is the sweep half of the no-allowlist bargain: the platform installs
# anything the public registry lists, so it has to keep noticing when an
# approved server's declared tools move underneath that approval (OWASP
# MCP03:2025 rug pull). The protocol's own `notifications/tools/list_changed`
# cannot be relied on — shipping agent clients ignore it — so the platform
# re-asks on its own schedule.
#
# Scope is deliberately narrow:
#   * only servers installed FROM THE CATALOG — a hand-authored server was
#     configured by someone who already knows what it is
#   * only servers with a baseline — nothing to compare against otherwise
#   * only remote transports — probing a stdio server would mean executing its
#     package here, which the platform does not do
#
# Per-user OAuth servers report :unauthorized and are counted, not failed: this
# process holds no user's token, and that is a gap to surface rather than an
# error to retry.

module Activities
  module MCP
    class ScanToolDriftActivity < ::Activities::Base
      def run(_input = nil)
        tally = Hash.new(0)

        scope.find_each do |server|
          # A server with no baseline has never been successfully probed, so the
          # sweep tries to establish one; otherwise it compares against it.
          outcome = if server.tool_baseline?
            ::MCP::ToolDriftDetector.check(server)
          else
            ::MCP::ToolDriftDetector.capture(server)
          end

          tally[outcome.status] += 1
          log(:warn, "tool drift on mcp_server #{server.id} (#{server.name}): #{outcome.drift.except('detected_at')}") if outcome.drifted?
          tally[:auth_detected] += 1 if adopt_auth_requirement(server, outcome)
        end

        log(:info, "tool drift scan: #{tally.sort.map { |k, v| "#{k}=#{v}" }.join(' ')}")
        tally.transform_keys(&:to_s)
      end

      private

      # A server that answers 401 requires a sign-in, whatever it was configured
      # as. Installs made before this was detected — and any row created outside
      # the install flow — otherwise sit as `auth_type: none` forever, looking
      # configured while no agent can actually use them. Recording the truth is
      # not a silent change of intent: the UI immediately shows "Not connected",
      # which is the accurate state.
      def adopt_auth_requirement(server, outcome)
        return false unless outcome.status == :unauthorized && server.auth_type_none? && !server.transport_stdio?

        server.update!(auth_type: :oauth)
        log(:info, "mcp_server #{server.id} (#{server.name}) requires sign-in; marked for OAuth")
        true
      end

      # Catalog installs on a remote transport. Servers without a baseline are
      # included on purpose: they are the ones most likely to be unauthenticated
      # or unreachable, which is exactly what the sweep should find out.
      def scope
        MCPServer.where.not(connector_name: nil).where.not(transport: "stdio")
      end
    end
  end
end
