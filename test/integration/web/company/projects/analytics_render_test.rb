# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::AnalyticsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "index renders the analytics page" do
    get company_project_analytics_path(@project)

    assert_response :success
    assert_inertia_page "Projects/Analytics/AnalyticsPage"
    assert_inertia_props scope: "project", period: "30d"
  end
end
