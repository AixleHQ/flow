# frozen_string_literal: true

module PersonalTools
  class ListMCPServers < Base
    tool do
      display_name "List MCP Servers"
      description "List the MCP servers configured in a project."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::MCPServersPolicy, project: project)

      rows = MCPServer.visible_for_project(project).limit(100).map do |m|
        { id: m.id, name: m.name, kind: m.kind,
          transport: m.transport, enabled: m.enabled }
      end
      success(project_id: project.id, mcp_servers: rows)
    end
  end
end
