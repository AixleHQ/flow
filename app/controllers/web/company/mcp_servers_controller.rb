# frozen_string_literal: true

class Web::Company::MCPServersController < Web::Company::ApplicationController
  def index
    servers = MCPServer.visible_for_company(current_company).order(kind: :asc, created_at: :desc)
    config_items = current_company.config_items.pluck(:name)

    render inertia: "Company/McpServers/Index", props: {
      mcp_servers: servers.map { |s| MCPServerResource.new(s).to_h },
      config_item_names: config_items
    }
  end

  def create
    server = current_company.mcp_servers.new(server_params)

    if server.save
      redirect_to company_mcp_servers_path, notice: "MCP server created"
    else
      redirect_to company_mcp_servers_path, inertia: { errors: server.errors }
    end
  end

  def update
    server = MCPServer.for_company(current_company).find(params[:id])

    if server.update(server_params)
      redirect_to company_mcp_servers_path, notice: "MCP server updated"
    else
      redirect_to company_mcp_servers_path, inertia: { errors: server.errors }
    end
  end

  def destroy
    server = MCPServer.for_company(current_company).find(params[:id])
    server.destroy
    redirect_to company_mcp_servers_path, notice: "MCP server deleted"
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
