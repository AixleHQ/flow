# frozen_string_literal: true

require "test_helper"

class Web::OnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(
      :user,
      company: @company,
      onboarding_state: "step1",
      password: AuthHelper::TEST_PASSWORD,
      password_confirmation: AuthHelper::TEST_PASSWORD
    )
    sign_in_as(@user)
  end

  test "show renders onboarding when not completed" do
    get onboarding_path
    assert_inertia_page "Onboarding/OnboardingPage"
  end

  test "update redirects on success" do
    patch onboarding_path, params: {
      onboarding: { position: "dev", preferred_agent_language: "en" }
    }
    assert_response :redirect
  end

  test "go_next advances from step1 to step2" do
    patch onboarding_path, params: {
      onboarding: { position: "dev", preferred_agent_language: "en", onboarding_state_event: "go_next" }
    }
    assert_equal "step2", @user.company_memberships.sole.reload.onboarding_state
  end

  test "viewer completes onboarding without agents" do
    viewer = create(:user, :viewer, company: @company, onboarding_state: "step2",
                                    position: "dev", preferred_agent_language: "en",
                                    email: "client2@ext.com",
                                    password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    sign_in_as(viewer)

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "complete" } }
    assert_equal "completed", viewer.company_memberships.sole.reload.onboarding_state
  end

  test "non-viewer cannot complete at step2 without agent credentials (silent no-op)" do
    membership = @user.company_memberships.sole
    membership.update!(onboarding_state: "step2", position: "dev", preferred_agent_language: "en")

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "complete" } }
    assert_equal "step2", membership.reload.onboarding_state
  end

  test "non-viewer completes onboarding at step2 with an agent credential" do
    membership = @user.company_memberships.sole
    membership.update!(onboarding_state: "step2", position: "dev", preferred_agent_language: "en")
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "complete" } }
    assert_equal "completed", membership.reload.onboarding_state
  end
end
