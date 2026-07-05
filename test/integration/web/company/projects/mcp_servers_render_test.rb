# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::MCPServersRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "index renders the mcp servers page with visible servers" do
    create(:mcp_server, scope: @project, kind: :custom)

    get company_project_mcp_servers_path(@project)
    assert_response :success
    assert_inertia_page "Projects/McpServers/McpServersPage"
  end
end
