# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::ToolsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders tools page" do
    get company_project_tools_path(@project)
    assert_inertia_page "Projects/Tools/ToolsPage"
  end

  test "create redirects on success" do
    post company_project_tools_path(@project), params: {
      tool: { name: "proj_tool", display_name: "Proj Tool", docker_image: "alpine:latest" }
    }
    assert_response :redirect
  end

  test "update redirects on success" do
    tool = create(:tool, :with_project_scope, scope: @project)

    patch company_project_tool_path(@project, tool), params: {
      tool: { display_name: "Updated" }
    }
    assert_response :redirect
  end

  test "destroy redirects" do
    tool = create(:tool, :with_project_scope, scope: @project)

    delete company_project_tool_path(@project, tool)
    assert_response :redirect
  end
end
