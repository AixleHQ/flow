# frozen_string_literal: true

require "test_helper"

class Web::ProfileControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "show renders profile page" do
    get profile_path
    assert_inertia_page "Profile/Show"
  end

  test "update redirects on success" do
    patch profile_path, params: { profile: { name: "Updated Name" } }
    assert_response :redirect
  end

  test "update_default_model redirects on success" do
    credential = create(:agent_credential, user: @user)

    put update_default_model_profile_path, params: {
      agent_credential_id: credential.id,
      default_model: "claude-sonnet-4-20250514"
    }

    assert_response :redirect
  end

  test "destroy_credential redirects on success" do
    credential = create(:agent_credential, user: @user)

    delete destroy_credential_profile_path, params: {
      agent_credential_id: credential.id
    }

    assert_response :redirect
  end
end
