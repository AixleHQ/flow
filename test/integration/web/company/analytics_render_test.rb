# frozen_string_literal: true

require "test_helper"

class Web::Company::AnalyticsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    Bullet.enable = false
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "index renders the analytics page" do
    get company_analytics_path

    assert_response :success
    assert_inertia_page "Company/Analytics/AnalyticsPage"
    assert_inertia_props scope: "company", period: "30d"
  end
end
