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

  test "inertia visit by a super admin is sent to the admin panel with a full-page visit" do
    super_admin = create(:user, :super_admin, :onboarding_completed, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(super_admin)

    # /admin is Administrate (server-rendered, not an Inertia screen). During an
    # Inertia XHR we must reply 409 + X-Inertia-Location so the client performs a
    # full-page visit. A plain redirect_to would return non-Inertia HTML, which
    # Inertia dumps into its error modal (admin page in a box over a dark backdrop).
    get company_projects_path, headers: { "X-Inertia" => "true" }

    assert_response :conflict
    assert_equal admin_root_path, response.headers["X-Inertia-Location"]
  end

  test "full page visit by a super admin is redirected to the admin panel" do
    super_admin = create(:user, :super_admin, :onboarding_completed, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(super_admin)

    get company_projects_path

    assert_redirected_to admin_root_path
  end
end
