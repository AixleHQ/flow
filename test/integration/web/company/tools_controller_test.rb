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

  test "destroy soft-deletes the tool and redirects" do
    tool = create(:tool, :with_company_scope, scope: @company)

    assert_no_difference "Tool.count" do
      delete company_tool_path(tool)
    end
    assert_response :redirect
    assert tool.reload.deleted?
  end

  test "destroy soft-deletes tool that has associated tool_results" do
    tool = create(:tool, :with_company_scope, scope: @company)
    create(:tool_result, tool: tool)

    assert_no_difference "Tool.count" do
      delete company_tool_path(tool)
    end
    assert_response :redirect
    assert tool.reload.deleted?
    assert_equal 1, tool.tool_results.count
  end

  test "create succeeds with the same name as a soft-deleted tool" do
    tool = create(:tool, :with_company_scope, scope: @company, name: "reused_name")
    tool.soft_delete!

    assert_difference "Tool.count", 1 do
      post company_tools_path, params: {
        tool: { name: "reused_name", display_name: "Reused", docker_image: "alpine:latest" }
      }
    end
    assert_response :redirect
  end
end
