# frozen_string_literal: true

class Web::Company::Projects::MCPServersController < Web::Company::Projects::ApplicationController
  def index
    # includes(:oauth_credentials): MCPServerResource#oauth_status reads the loaded
    # association in memory, so the status column is not an N+1 across the list.
    # :manual_oauth_client for the same reason — the form needs to know whether one
    # is configured, on every row.
    servers = MCPServer.visible_for_project(current_project)
                       .includes(:oauth_credentials, :manual_oauth_client)
                       .order(kind: :asc, created_at: :desc)
    config_items = ConfigItem.visible_for_project(current_project).pluck(:name)

    render inertia: "Projects/McpServers/McpServersPage", props: {
      project: project_props,
      # params[:user] lets oauth_status resolve the CURRENT viewer's credential for
      # per_user servers (otherwise every per_user server reads "Not connected").
      mcp_servers: servers.map { |s|
        MCPServerResource.new(s, params: {
          user: current_user,
          connector_statuses: catalog_index(servers).transform_values(&:first),
          connector_versions: catalog_index(servers).transform_values(&:last)
        }).to_h
      },
      config_item_names: config_items,
      # The connector catalog is a second way to add an MCP server, not a
      # separate resource, so it is served with this page and browsed from it.
      # Searching partial-reloads only these two props.
      connectors: catalog_connectors.map { |c| ConnectorResource.new(c).to_h },
      connector_query: connector_query,
      catalog_synced_at: Connector.maximum(:updated_at)
    }
  end

  def create
    server = current_project.mcp_servers.new(server_params)

    if server.save
      sync_manual_oauth_client(server)
      redirect_to company_project_mcp_servers_path(current_project), notice: "MCP server created"
    else
      redirect_to company_project_mcp_servers_path(current_project), inertia: { errors: server.errors }
    end
  end

  def update
    server = current_project.mcp_servers.find(params[:id])

    if server.update(server_params(existing: server))
      sync_manual_oauth_client(server)
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

  # Moves an install to the version the catalog now carries. Explicit on purpose:
  # updating changes which code runs, which is exactly what pinning a version
  # exists to prevent happening quietly.
  def update_connector
    server = current_project.mcp_servers.find(params[:id])
    connector = Connector.find_by(name: server.connector_name)
    return redirect_back_with(alert: "This connector is no longer in the catalog") if connector.nil?

    MCP::ConnectorUpdater.apply(server: server, connector: connector, values: install_values)
    redirect_to company_project_mcp_servers_path(current_project),
                notice: "#{server.name} updated to #{server.connector_version}"
  rescue MCP::ConnectorUpdater::Error, ActiveRecord::RecordInvalid => e
    redirect_back_with(alert: e.message)
  end

  # Takes the server's current tool declarations as the approved baseline.
  # Deliberately a human action on its own route: the drift sweep never moves
  # a baseline by itself, or a rug pull would normalise itself away.
  def accept_tool_drift
    server = current_project.mcp_servers.find(params[:id])
    outcome = MCP::ToolDriftDetector.accept(server)

    notice = outcome.status == :ok ? "Tool changes accepted for #{server.name}" : nil
    alert = notice ? nil : "Could not re-check #{server.name} (#{outcome.status}). Nothing was accepted."

    redirect_to company_project_mcp_servers_path(current_project), notice: notice, alert: alert
  end

  private

  # Comfortably above the curated seed (32 entries) so the default view is never
  # a truncated version of it, and roomy enough that a search rarely hides a
  # match behind a limit the UI does not mention.
  CATALOG_PAGE_SIZE = 60
  SCALAR_TYPES = [ String, Numeric, TrueClass, FalseClass ].freeze

  # Answers for inputs the new version newly declares. Same coercion rule as the
  # install path: scalars and arrays of scalars only, nested structures dropped
  # at the door rather than trusted to be ignored downstream.
  def install_values
    raw = params[:values]
    return {} unless raw.respond_to?(:to_unsafe_h)

    raw.to_unsafe_h.each_with_object({}) do |(key, value), memo|
      memo[key.to_s] = value.to_s if SCALAR_TYPES.any? { |type| value.is_a?(type) }
    end
  end

  def redirect_back_with(alert:)
    redirect_to company_project_mcp_servers_path(current_project), alert: alert
  end

  # One query for the whole list: every catalog-installed server needs its
  # connector's CURRENT status and version, and resolving those per row would be
  # an N+1 across a page of servers.
  def catalog_index(servers)
    @catalog_index ||= begin
      names = servers.filter_map(&:connector_name).uniq
      rows = names.any? ? Connector.where(name: names).pluck(:name, :status, :version) : []
      rows.to_h { |name, status, version| [ name, [ status, version ] ] }
    end
  end

  def connector_query
    params[:connector_q].to_s.strip
  end

  # Two different jobs, so two different scopes.
  #
  # SEARCH goes over the whole mirror — ~19.5k entries — because that is the
  # point of holding a local copy: the registry API can only match server-name
  # substrings, so "issue tracker" finds nothing upstream.
  #
  # The DEFAULT view shows the curated set only. The open registry is mostly
  # long tail: thousands of generated and abandoned entries whose only ranking
  # signal is how recently they were published. Opening on "everything, ordered
  # by something weak" teaches people the catalog is noise. Opening on a list
  # assembled from measured popularity teaches them it is worth searching.
  #
  # The trade is real and deliberate: everything outside the curated set is
  # reachable by search alone, never by browsing.
  def catalog_connectors
    return Connector.discoverable.search(connector_query).limit(CATALOG_PAGE_SIZE) if connector_query.present?

    Connector.discoverable.where(featured: true).popular.limit(CATALOG_PAGE_SIZE)
  end

  # The masking sentinel MCPServerResource serializes in place of every stored
  # header/env value (must match MASK in McpServerFormModal.tsx).
  SECRET_MASK = ("•" * 6).freeze

  def preserved_param_paths
    [ [ :mcpServer, :env ], [ :mcpServer, :headers ], [ :values ] ]
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

  # Credentials for an authorization server that will not let us register ourselves
  # (see MCP::RegistrationError). Only the client id and secret are hand-entered —
  # the endpoints still come from discovery on the next connect, which is why a row
  # is saved here with neither.
  #
  # Clearing the client id deletes the client, and with it (dependent: :destroy) the
  # credentials obtained through it: they were issued to that OAuth app and are worth
  # nothing without it.
  def sync_manual_oauth_client(server)
    return unless params[:mcp_server].key?(:oauth_client_id)

    client_id = params[:mcp_server][:oauth_client_id].to_s.strip
    return server.manual_oauth_client&.destroy if client_id.blank?

    client = server.manual_oauth_client || server.build_manual_oauth_client(source: OauthClient::SOURCE_MANUAL)
    client.client_id = client_id
    secret = params[:mcp_server][:oauth_client_secret].to_s
    client.client_secret = secret.presence unless secret == SECRET_MASK
    client.save!
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
