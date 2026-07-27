# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::ConfigItemsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "index renders the config page" do
    # visible_for_project surfaces both company- and project-scoped items
    create(:config_item, scope: @project)
    create(:config_item, scope: @project)

    get company_project_config_items_path(@project)

    assert_response :success
    assert_inertia_page "Projects/Config/ConfigPage"
  end
end
