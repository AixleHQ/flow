# frozen_string_literal: true

require "test_helper"

class Web::Company::ToolsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders tools page" do
    get company_tools_path
    assert_inertia_page "Company/Tools/Index"
  end

  test "create redirects on success" do
    post company_tools_path, params: {
      tool: { name: "my_tool", display_name: "My Tool", docker_image: "alpine:latest" }
    }
    assert_response :redirect
  end

  test "update redirects on success" do
    tool = create(:tool, :with_company_scope, scope: @company)

    patch company_tool_path(tool), params: {
      tool: { display_name: "Updated" }
    }
    assert_response :redirect
  end

  test "destroy redirects" do
    tool = create(:tool, :with_company_scope, scope: @company)

    delete company_tool_path(tool)
    assert_response :redirect
  end
end
