# frozen_string_literal: true

class Web::Company::Projects::MCPServersController < Web::Company::Projects::ApplicationController
  def index
    servers = MCPServer.visible_for_project(current_project).order(kind: :asc, created_at: :desc)
    config_items = current_company.config_items.pluck(:name)

    render inertia: "Projects/McpServers/McpServersPage", props: {
      project: project_props,
      mcp_servers: servers.map { |s| MCPServerResource.new(s).to_h },
      config_item_names: config_items
    }
  end

  def create
    server = current_project.mcp_servers.new(server_params)

    if server.save
      redirect_to company_project_mcp_servers_path(current_project), notice: "MCP server created"
    else
      redirect_to company_project_mcp_servers_path(current_project), inertia: { errors: server.errors }
    end
  end

  def update
    server = current_project.mcp_servers.find(params[:id])

    if server.update(server_params)
      redirect_to company_project_mcp_servers_path(current_project), notice: "MCP server updated"
    else
      redirect_to company_project_mcp_servers_path(current_project), inertia: { errors: server.errors }
    end
  end

  def destroy
    server = current_project.mcp_servers.find(params[:id])
    server.destroy
    redirect_to company_project_mcp_servers_path(current_project), notice: "MCP server deleted"
  end

  private

  def preserved_param_paths
    [ [ :mcpServer, :env ], [ :mcpServer, :headers ] ]
  end

  def server_params
    params.require(:mcp_server).permit(
      :name, :display_name, :url, :transport, :description, :enabled,
      :command, headers: {}, env: {}
    ).merge(kind: :custom)
  end
end
