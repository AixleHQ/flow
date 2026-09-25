# frozen_string_literal: true

module PersonalTools
  class DeleteMCPServer < Base
    tool do
      display_name "Delete MCP Server"
      description "Archive a custom MCP server. New sessions stop getting it; its history and OAuth connections are kept and it can be restored from the MCP servers page. Refused while a workflow uses it."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :mcp_server_id, type: :integer, description: "MCP server id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :destroy?, policy: Web::Company::Projects::MCPServersPolicy, project: project)
      server = project.mcp_servers.where(kind: :custom).unarchived.find_by(id: params[:mcp_server_id])
      return error("Custom MCP server not found in this project") unless server

      name = server.name
      Versions.archive!(server, actor: version_actor)
      success(archived_mcp_server_id: server.id, name: name)
    end
  end
end
