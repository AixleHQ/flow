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
    create(:config_item, name: "COMPANY_KEY", scope: @company)
    create(:config_item, name: "PROJECT_KEY", scope: @project)

    get company_project_mcp_servers_path(@project)

    assert_inertia_page "Projects/McpServers/McpServersPage"
    assert_inertia_props do |props|
      names = props[:config_item_names] || props[:configItemNames]
      %w[COMPANY_KEY PROJECT_KEY].all? { |name| names.include?(name) }
    end
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

  test "update rejects company-scoped server" do
    server = create(:mcp_server, scope: @company, kind: :custom, display_name: "Company MCP")

    patch company_project_mcp_server_path(@project, server), params: {
      mcp_server: { display_name: "Updated from project" }
    }

    assert_response :not_found
    assert_equal "Company MCP", server.reload.display_name
  end

  test "destroy redirects" do
    server = create(:mcp_server, scope: @project, kind: :custom)

    delete company_project_mcp_server_path(@project, server)
    assert_response :redirect
  end

  test "destroy rejects company-scoped server" do
    server = create(:mcp_server, scope: @company, kind: :custom)

    assert_no_difference -> { MCPServer.count } do
      delete company_project_mcp_server_path(@project, server)
    end

    assert_response :not_found
  end
end
