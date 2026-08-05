# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::MCPServersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders mcp servers page" do
    get company_project_mcp_servers_path(@project)
    assert_inertia_page "Projects/McpServers/McpServersPage"
  end

  test "index includes company and project config item names" do
    create(:config_item, name: "COMPANY_KEY", scope: @project)
    create(:config_item, name: "PROJECT_KEY", scope: @project)

    get company_project_mcp_servers_path(@project)

    assert_inertia_page "Projects/McpServers/McpServersPage"
    assert_inertia_props do |props|
      names = props[:config_item_names] || props[:configItemNames]
      %w[COMPANY_KEY PROJECT_KEY].all? { |name| names.include?(name) }
    end
  end

  # The masking sentinel MCPServerResource serializes for every stored secret
  # (must match SECRET_MASK in the controller / MASK in the modal).
  SECRET_MASK = "••••••"

  test "create redirects on success" do
    post company_project_mcp_servers_path(@project), params: {
      mcp_server: { name: "test-mcp", url: "https://mcp.test/v1", transport: "sse" }
    }
    assert_response :redirect
  end

  # The form posts one free-form line; storage keeps the executable and its argv
  # apart — the shape .mcp.json needs, and the shape a catalog install already
  # arrives in. (MCPServerResource joins it back for the field; see its own test.)
  test "a stdio server posted as one line is stored split" do
    post company_project_mcp_servers_path(@project), params: {
      mcp_server: { name: "local-mcp", transport: "stdio", command: "uvx local-mcp-server --verbose" }
    }

    server = MCPServer.find_by(name: "local-mcp")
    assert_equal "uvx", server.command
    assert_equal [ "local-mcp-server", "--verbose" ], server.args
  end

  test "a stdio command the agent image cannot launch is refused with a reason" do
    post company_project_mcp_servers_path(@project), params: {
      mcp_server: { name: "docker-mcp", transport: "stdio", command: "docker run -i ghcr.io/example/mcp" }
    }

    assert_nil MCPServer.find_by(name: "docker-mcp")
    assert_match(/Docker/, Array(session["inertia_errors"][:command]).to_sentence)
  end

  test "create persists auth_type and credential_scope so the OAuth flow is reachable" do
    post company_project_mcp_servers_path(@project), params: {
      mcp_server: { name: "oauth-mcp", url: "https://mcp.test/v1",
                    transport: "http", auth_type: "oauth", credential_scope: "per_user" }
    }
    assert_response :redirect

    server = @project.mcp_servers.find_by(name: "oauth-mcp")
    assert_equal "oauth", server.auth_type
    assert_equal "per_user", server.credential_scope
  end

  test "update preserves an untouched masked header instead of wiping it" do
    server = create(:mcp_server, scope: @project, kind: :custom, transport: "sse",
                    headers: { "Authorization" => "super-secret" })

    # The UI resubmits the untouched value as the sentinel (never the real secret).
    patch company_project_mcp_server_path(@project, server), params: {
      mcpServer: { description: "Renamed", headers: { "Authorization" => SECRET_MASK } }
    }
    assert_response :redirect

    server.reload
    assert_equal "Renamed", server.description
    assert_equal({ "Authorization" => "super-secret" }, server.headers)
  end

  test "update stores a freshly edited header value" do
    server = create(:mcp_server, scope: @project, kind: :custom, transport: "sse",
                    headers: { "Authorization" => "old-secret" })

    patch company_project_mcp_server_path(@project, server), params: {
      mcpServer: { headers: { "Authorization" => "rotated-secret" } }
    }
    assert_response :redirect

    assert_equal({ "Authorization" => "rotated-secret" }, server.reload.headers)
  end

  test "update deletes a header the user removed in the UI" do
    server = create(:mcp_server, scope: @project, kind: :custom, transport: "sse",
                    headers: { "Authorization" => "secret", "X-Extra" => "keep" })

    # Authorization is absent from the payload (removed); X-Extra stays (masked).
    patch company_project_mcp_server_path(@project, server), params: {
      mcpServer: { headers: { "X-Extra" => SECRET_MASK } }
    }
    assert_response :redirect

    assert_equal({ "X-Extra" => "keep" }, server.reload.headers)
  end

  test "update redirects on success" do
    server = create(:mcp_server, scope: @project, kind: :custom)

    patch company_project_mcp_server_path(@project, server), params: {
      mcp_server: { description: "Updated" }
    }
    assert_response :redirect
  end

  test "destroy redirects" do
    server = create(:mcp_server, scope: @project, kind: :custom)

    delete company_project_mcp_server_path(@project, server)
    assert_response :redirect
  end

  # ---------------------------------------------- connector catalog (same page)
  # The catalog is a second way to add an MCP server, not a separate screen, so
  # it is served with this page and browsed from it.

  test "index serves the connector catalog alongside installed servers" do
    manifest = MCP::ConnectorManifest.normalize(JSON.parse(file_fixture("mcp_registry/remote_http_secret_header.json").read))
    create(:connector, name: manifest["name"], title: manifest["title"], manifest: manifest, featured: true)

    get company_project_mcp_servers_path(@project)

    assert_inertia_props do |props|
      connector = props[:connectors].sole

      assert_equal "ai.adadvisor/mcp-server", connector[:name]
      assert connector[:installable]
      assert_equal [ "Authorization" ], connector[:targets].first[:inputs].map { |i| i[:key] }
    end
  end

  test "index searches the catalog by description, which the registry API cannot do" do
    create(:connector, title: "Acme Tracker", description: "Manage issues and bug tracking")
    create(:connector, title: "Unrelated", description: "Sends email")

    get company_project_mcp_servers_path(@project, connector_q: "bug tracking")

    assert_inertia_props do |props|
      assert_equal [ "Acme Tracker" ], props[:connectors].map { |c| c[:title] }
      assert_equal "bug tracking", props[:connectorQuery]
    end
  end

  test "index hides catalog entries the registry deleted" do
    create(:connector, :deleted, title: "Pulled")

    get company_project_mcp_servers_path(@project)

    assert_inertia_props { |props| assert_empty props[:connectors] }
  end

  test "index sends input declarations but never values" do
    manifest = MCP::ConnectorManifest.normalize(JSON.parse(file_fixture("mcp_registry/remote_http_secret_header.json").read))
    create(:connector, name: manifest["name"], manifest: manifest, featured: true)

    get company_project_mcp_servers_path(@project)

    assert_inertia_props do |props|
      input = props[:connectors].sole[:targets].first[:inputs].sole

      assert input[:secret]
      assert_not input.key?(:value), "declarations only — no values travel to the browser"
    end
  end
end
