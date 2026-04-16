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

  test "create redirects on success" do
    post company_project_mcp_servers_path(@project), params: {
      mcp_server: { name: "test-mcp", display_name: "Test MCP", url: "https://mcp.test/v1", transport: "sse" }
    }
    assert_response :redirect
  end

  test "update redirects on success" do
    server = create(:mcp_server, scope: @project, kind: :custom)

    patch company_project_mcp_server_path(@project, server), params: {
      mcp_server: { display_name: "Updated" }
    }
    assert_response :redirect
  end

  test "destroy redirects" do
    server = create(:mcp_server, scope: @project, kind: :custom)

    delete company_project_mcp_server_path(@project, server)
    assert_response :redirect
  end
end
