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

  test "viewer advances from step3 to step4 without agent credentials" do
    viewer = create(:user, :viewer, company: @company, onboarding_state: "step3",
                                    position: "dev", preferred_agent_language: "en",
                                    email: "client@ext.com",
                                    password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    sign_in_as(viewer)

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "go_next" } }
    assert_equal "step4", viewer.company_memberships.sole.reload.onboarding_state
  end

  test "non-viewer stays at step3 without agent credentials (silent no-op)" do
    membership = @user.company_memberships.sole
    membership.update!(onboarding_state: "step3", position: "dev", preferred_agent_language: "en")

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "go_next" } }
    assert_equal "step3", membership.reload.onboarding_state
  end

  test "viewer completes onboarding without agents" do
    viewer = create(:user, :viewer, company: @company, onboarding_state: "step4",
                                    position: "dev", preferred_agent_language: "en",
                                    email: "client2@ext.com",
                                    password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    sign_in_as(viewer)

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "complete" } }
    assert_equal "completed", viewer.company_memberships.sole.reload.onboarding_state
  end

  test "viewer PATCH with viewer_advance event advances from step2 to step4" do
    viewer = create(:user, :viewer, company: @company, onboarding_state: "step2",
                                    position: "dev", preferred_agent_language: "en",
                                    email: "client3@ext.com",
                                    password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    sign_in_as(viewer)

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "viewer_advance" } }
    assert_redirected_to onboarding_path
    assert_equal "step4", viewer.reload.onboarding_state
  end

  test "non-viewer cannot use viewer_advance event" do
    @user.update!(onboarding_state: "step2", position: "dev", preferred_agent_language: "en")

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "viewer_advance" } }
    assert_equal "step2", @user.reload.onboarding_state
  end
end
