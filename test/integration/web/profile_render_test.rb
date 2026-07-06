# frozen_string_literal: true

require "test_helper"

class Web::ProfileRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    Bullet.enable = false
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "show renders the profile page" do
    get profile_path

    assert_response :success
    assert_inertia_page "Profile/Show"
  end

  test "usage renders the profile usage page" do
    # All analytics props are InertiaRails.defer blocks that don't run on the
    # initial full-page GET, so no session/usage data is needed to render.
    get usage_profile_path

    assert_response :success
    assert_inertia_page "Profile/Usage"
  end
end
