# frozen_string_literal: true

module Coder
  # MCPServerSyncService — idempotently upsert the managed `MCPServer` row
  # that mirrors a Coder integration.
  #
  # Each Coder integration owns exactly one managed MCP server (1:1 via
  # `mcp_servers.integration_id` FK, see DD-17). The MCP server is what
  # binds the three Coder MCP tools (`coder_allocate_machine`,
  # `coder_ssh_exec`, `coder_release_machine`) to *this* integration at
  # tool-call time. Lifecycle: created on connect, refreshed on settings
  # update, destroyed by FK cascade on disconnect.
  class MCPServerSyncService
    def initialize(integration)
      @integration = integration
    end

    def sync!
      raise ArgumentError, "expected Coder integration" unless @integration.provider.to_s == "coder"

      server = MCPServer.find_or_initialize_by(integration_id: @integration.id)
      server.assign_attributes(
        kind:         :managed,
        name:         managed_name,
        description:  "Coder MCP for #{@integration.name}",
        transport:    :http,
        scope_type:   @integration.project_id.present? ? "Project" : "Company",
        scope_id:     @integration.project_id || @integration.company_id,
        enabled:      @integration.active?
      )
      server.save!
      server
    end

    private

    def managed_name
      "coder-#{@integration.id}"
    end
  end
end
