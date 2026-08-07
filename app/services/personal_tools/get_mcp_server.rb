# frozen_string_literal: true

module PersonalTools
  # `list_mcp_servers` answers "what is wired up here" in five fields. This
  # answers "should I trust and use this one": where it points, what it was
  # installed from, whether its tool declarations moved after approval, and
  # whether the caller still has to sign in.
  class GetMCPServer < Base
    tool do
      display_name "Get MCP Server"
      description "Return one configured MCP server in full: transport and endpoint, connector provenance " \
                  "and version, tool-baseline drift, and auth state. Header and env VALUES are never " \
                  "returned — only which keys exist."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :mcp_server_id, type: :integer, description: "MCP server id (see list_mcp_servers).", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::MCPServersPolicy, project: project)

      server = MCPServer.visible_for_project(project).find_by(id: params[:mcp_server_id])
      return error("MCP server not found in this project") unless server

      success({ id: server.id, name: server.name, kind: server.kind, enabled: server.enabled,
                transport: server.transport, url: server.url, command: server.command_line.presence,
                description: server.description,
                auth_type: server.auth_type.to_s, credential_scope: server.credential_scope.to_s,
                # Keys only: a value here can be a bearer token or an API key, and a
                # read tool has no business handing those back out (see MCPServerResource).
                header_names: (server.headers || {}).keys, env_names: (server.env || {}).keys }
                .merge(connector_provenance(server)).merge(tool_health(server)))
    end

    private

    def connector_provenance(server)
      return { from_connector: false } unless server.from_connector?

      catalog = Connector.find_by(name: server.connector_name)
      { from_connector: true, connector_name: server.connector_name,
        connector_version: server.connector_version,
        # An unpinned package install can resolve a different release at any session
        # start — the one shape a rug pull can move under us, so it is stated.
        connector_version_pinned: server.connector_version_pinned?,
        # "deleted" means the registry pulled the entry (possible spam or malware);
        # the install keeps working, so the warning has to travel with the read.
        catalog_status: catalog&.status&.to_s,
        catalog_version: catalog&.version,
        update_available: update_available?(server, catalog) }
    end

    def update_available?(server, catalog)
      return false if catalog.nil? || catalog.version.blank? || server.connector_version.blank?

      catalog.version != server.connector_version
    end

    # stdio servers are never probed (that would mean running their package here),
    # so a missing baseline is "not checked", never "verified clean".
    def tool_health(server)
      { tool_baseline_recorded: server.tool_baseline?, tool_drift: server.tool_drift.presence }
    end
  end
end
