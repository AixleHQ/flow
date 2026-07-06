# frozen_string_literal: true

require "test_helper"

class Web::Company::ConfigItemsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    Bullet.enable = false
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "index renders the config items page" do
    get company_config_items_path
    assert_response :success
    assert_inertia_page "Company/ConfigItems/Index"
  end
end
