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
end
