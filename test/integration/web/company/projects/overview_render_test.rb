# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::OverviewRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "index renders the overview page" do
    get company_project_overview_index_path(@project)

    assert_response :success
    assert_inertia_page "Projects/Overview/OverviewPage"
  end
end
