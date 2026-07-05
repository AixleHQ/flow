# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::ToolsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "index renders the tools page" do
    # visible_for_project + ui_visible surfaces in-scope custom (db) tools
    create(:tool, :with_project_scope, scope: @project)

    get company_project_tools_path(@project)

    assert_response :success
    assert_inertia_page "Projects/Tools/ToolsPage"
    assert_inertia_props do |props|
      props[:tools].length >= 1
    end
  end
end
