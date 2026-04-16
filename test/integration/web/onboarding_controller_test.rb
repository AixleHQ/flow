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
end
