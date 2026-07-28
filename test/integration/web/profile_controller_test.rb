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

  # Regression: the profile form edits the name (User) AND the agent language,
  # which is a per-company onboarding answer on the MEMBERSHIP. Permitting only
  # :name in profile_params made language changes silently no-op.
  test "update saves the agent language onto the CURRENT membership" do
    patch profile_path, params: { profile: { name: "Updated Name", preferred_agent_language: "ru" } }

    assert_response :redirect
    assert_equal "Updated Name", @user.reload.name
    assert_equal "ru", @user.company_memberships.find_by!(company: @company).preferred_agent_language
  end

  test "update leaves the OTHER company's language alone" do
    other = create(:company)
    other_membership = create(:company_membership, user: @user, company: other,
                                                   preferred_agent_language: "en")

    patch profile_path, params: { profile: { preferred_agent_language: "ru" } }

    assert_equal "ru", @user.company_memberships.find_by!(company: @company).preferred_agent_language
    assert_equal "en", other_membership.reload.preferred_agent_language
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
