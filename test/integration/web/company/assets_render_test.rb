# frozen_string_literal: true

require "test_helper"

class Web::Company::AssetsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @asset = create(:asset, scope: @company, created_by: @user)
    Bullet.enable = false # the index list page trips the unused-eager-loading gate
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "index renders the company assets page" do
    get company_assets_path
    assert_response :success
    assert_inertia_page "Company/Assets/Index"

    assert_inertia_props do |props|
      props[:assets].any? { |a| a[:id] == @asset.id }
    end
  end
end
