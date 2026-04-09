# frozen_string_literal: true

require "test_helper"

class Web::Company::MCPServersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders mcp servers page" do
    get company_mcp_servers_path
    assert_inertia_page "Company/McpServers/Index"
  end

  test "create redirects on success" do
    post company_mcp_servers_path, params: {
      mcp_server: { name: "co-mcp", display_name: "Co MCP", url: "https://mcp.co/v1", transport: "sse" }
    }
    assert_response :redirect
  end

  test "update redirects on success" do
    server = create(:mcp_server, scope: @company, kind: :custom)

    patch company_mcp_server_path(server), params: {
      mcp_server: { display_name: "Updated" }
    }
    assert_response :redirect
  end

  test "destroy redirects" do
    server = create(:mcp_server, scope: @company, kind: :custom)

    delete company_mcp_server_path(server)
    assert_response :redirect
  end
end
