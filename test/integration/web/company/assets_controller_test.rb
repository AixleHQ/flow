# frozen_string_literal: true

require "test_helper"

class Web::Company::AssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders assets page" do
    get company_assets_path
    assert_inertia_page "Company/Assets/Index"
  end
end
