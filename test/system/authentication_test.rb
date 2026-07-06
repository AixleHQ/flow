# frozen_string_literal: true

require "application_system_test_case"

# E2E critical path: real login flow through the Inertia/React SPA in a headless
# browser (docs/testing.md §1).
class AuthenticationTest < ApplicationSystemTestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company,
                                  password: AuthHelper::TEST_PASSWORD)
  end

  test "user logs in with valid credentials and lands on the projects page" do
    login = LoginPage.new
    login.load
    login.sign_in(@user.email, AuthHelper::TEST_PASSWORD)

    assert_current_path "/company/projects", wait: 10
    assert_selector "button", text: "Create Project"
  end

  test "invalid credentials keep the user on the login page" do
    login = LoginPage.new
    login.load
    login.sign_in(@user.email, "wrong-password")

    assert_current_path "/login", wait: 10
    assert login.has_submit_button?, "expected to remain on the login form"
  end
end
