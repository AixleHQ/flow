# frozen_string_literal: true

class Web::Company::Projects::MCPServersController < Web::Company::Projects::ApplicationController
  def index
    # includes(:oauth_credentials): MCPServerResource#oauth_status reads the loaded
    # association in memory, so the status column is not an N+1 across the list.
    servers = MCPServer.visible_for_project(current_project)
                       .includes(:oauth_credentials)
                       .order(kind: :asc, created_at: :desc)
    config_items = ConfigItem.visible_for_project(current_project).pluck(:name)

    render inertia: "Projects/McpServers/McpServersPage", props: {
      project: project_props,
      # params[:user] lets oauth_status resolve the CURRENT viewer's credential for
      # per_user servers (otherwise every per_user server reads "Not connected").
      mcp_servers: servers.map { |s| MCPServerResource.new(s, params: { user: current_user }).to_h },
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

    if server.update(server_params(existing: server))
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

  # The masking sentinel MCPServerResource serializes in place of every stored
  # header/env value (must match MASK in McpServerFormModal.tsx).
  SECRET_MASK = ("•" * 6).freeze

  def preserved_param_paths
    [ [ :mcpServer, :env ], [ :mcpServer, :headers ] ]
  end

  # @param existing [MCPServer, nil] the record being updated (nil on create)
  def server_params(existing: nil)
    permitted = params.require(:mcp_server).permit(
      :name, :url, :transport, :description, :enabled,
      :command, :auth_type, :credential_scope, headers: {}, env: {}
    ).merge(kind: :custom)

    unmask_secrets!(permitted, existing)
    permitted
  end

  # Restore untouched secrets on edit: the UI resubmits unchanged header/env
  # values as the masking sentinel (it never sees the real secret), so swap each
  # sentinel back to the currently-stored value. Keys the user removed in the UI
  # are absent from the submission and stay removed; freshly-entered values pass
  # through. Without this, a plain update! wipes every untouched secret.
  def unmask_secrets!(permitted, existing)
    %i[headers env].each do |field|
      submitted = permitted[field]
      next if submitted.nil?

      stored = (existing&.public_send(field) || {})
      permitted[field] = submitted.to_h.each_with_object({}) do |(key, value), memo|
        resolved = value == SECRET_MASK ? stored[key.to_s] : value
        memo[key] = resolved unless resolved.nil?
      end
    end
  end
end
