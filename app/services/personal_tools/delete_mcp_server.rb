# frozen_string_literal: true

module PersonalTools
  class DeleteMCPServer < Base
    tool do
      display_name "Delete MCP Server"
      description "Delete a custom MCP server."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :mcp_server_id, type: :integer, description: "MCP server id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :destroy?, policy: Web::Company::Projects::MCPServersPolicy, project: project)
      server = project.mcp_servers.where(kind: :custom).find_by(id: params[:mcp_server_id])
      return error("Custom MCP server not found in this project") unless server

      name = server.name
      server.destroy
      success(deleted_mcp_server_id: params[:mcp_server_id].to_i, name: name)
    end
  end
end
