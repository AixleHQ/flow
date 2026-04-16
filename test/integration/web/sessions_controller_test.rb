# frozen_string_literal: true

require "test_helper"

class Web::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
  end

  test "new renders login page when not signed in" do
    get login_path
    assert_inertia_page "Auth/LoginPage"
  end

  test "new redirects to projects when already signed in" do
    sign_in_as(@user)

    get login_path
    assert_response :redirect
  end

  test "create signs in and redirects on valid credentials" do
    post login_path, params: {
      user: { email: @user.email, password: AuthHelper::TEST_PASSWORD }
    }

    assert_response :redirect
  end

  test "create redirects back to login on invalid credentials" do
    post login_path, params: {
      user: { email: @user.email, password: "wrong_password" }
    }

    assert_redirected_to login_path
  end

  test "destroy signs out and redirects to login" do
    sign_in_as(@user)

    delete logout_path
    assert_redirected_to login_path
  end

  test "failure redirects to login with error" do
    get auth_failure_path(message: "invalid_credentials")
    assert_redirected_to login_path(error: "invalid_credentials")
  end
end
