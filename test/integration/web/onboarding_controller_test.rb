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
      onboarding: { position: "engineering", preferred_agent_language: "en" }
    }
    assert_response :redirect
  end

  test "an onboarding page loaded before positions became areas still saves the area" do
    patch onboarding_path, params: { onboarding: { position: "pm_po_ba", preferred_agent_language: "en" } }

    assert_equal "product", @user.company_memberships.sole.reload.position
  end

  test "go_next advances from step1 to step2" do
    patch onboarding_path, params: {
      onboarding: { position: "engineering", preferred_agent_language: "en", onboarding_state_event: "go_next" }
    }
    assert_equal "step2", @user.company_memberships.sole.reload.onboarding_state
  end

  test "a viewer finishes onboarding from the profile step without an agent" do
    viewer = create(:user, :viewer, company: @company, onboarding_state: "step1",
                                    email: "client2@ext.com",
                                    password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    sign_in_as(viewer)

    patch onboarding_path, params: {
      onboarding: { position: "engineering", preferred_agent_language: "en", onboarding_state_event: "complete" }
    }

    membership = viewer.company_memberships.sole.reload
    assert_equal "completed", membership.onboarding_state
    assert_equal "engineering", membership.position
  end

  test "non-viewer cannot complete at step2 without agent credentials (silent no-op)" do
    membership = @user.company_memberships.sole
    membership.update!(onboarding_state: "step2", position: "engineering", preferred_agent_language: "en")

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "complete" } }
    assert_equal "step2", membership.reload.onboarding_state
  end

  test "an admin skips the agent step and lands in the app" do
    admin = create(:user, :admin, company: @company, onboarding_state: "step2",
                                  position: "executive", preferred_agent_language: "en", email: "admin2@example.com",
                                  password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    sign_in_as(admin)

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "skip_agent_setup" } }
    follow_redirect!

    membership = admin.company_memberships.sole.reload
    assert_equal "completed", membership.onboarding_state
    assert membership.agent_setup_skipped_at.present?
    assert_redirected_to company_projects_path
  end

  test "an employee skips the agent step and lands in the app" do
    membership = @user.company_memberships.sole
    membership.update!(onboarding_state: "step2", position: "engineering", preferred_agent_language: "en")

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "skip_agent_setup" } }
    follow_redirect!

    membership.reload
    assert_equal "completed", membership.onboarding_state
    assert membership.agent_setup_skipped_at.present?
    assert_redirected_to company_projects_path
  end

  test "non-viewer completes onboarding at step2 with an agent credential" do
    membership = @user.company_memberships.sole
    membership.update!(onboarding_state: "step2", position: "engineering", preferred_agent_language: "en")
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")

    patch onboarding_path, params: { onboarding: { onboarding_state_event: "complete" } }
    assert_equal "completed", membership.reload.onboarding_state
  end
end
