# frozen_string_literal: true

require "test_helper"

class Web::AdminSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD)
  end

  test "an unsigned-in visit to the admin panel is sent to the admin sign-in" do
    get admin_root_path

    assert_redirected_to admin_login_path
  end

  test "new renders the admin sign-in page" do
    get admin_login_path

    assert_inertia_page "Auth/AdminLoginPage"
  end

  test "a super admin signs in with a password and lands in the admin panel" do
    post admin_login_path, params: { email: @operator.email, password: AuthHelper::TEST_PASSWORD }

    assert_redirected_to admin_root_path
    follow_redirect!
    assert_response :success
    assert_equal @operator, UserSession.live.sole.user
  end

  test "an Inertia sign-in gets a full-page visit to the admin panel" do
    post admin_login_path, params: { email: @operator.email, password: AuthHelper::TEST_PASSWORD },
                           headers: { "X-Inertia" => "true" }

    assert_response :conflict
    assert_equal admin_root_path, response.headers["X-Inertia-Location"]
  end

  # /login offers methods by the address's domain; the operator's domain belongs
  # to no workspace, so that screen never reaches a password step for them.
  test "a super admin whose domain no workspace claims still gets in" do
    post login_identify_path, params: { email: @operator.email }
    assert_redirected_to login_path(error: "no_workspace")

    post admin_login_path, params: { email: @operator.email, password: AuthHelper::TEST_PASSWORD }

    assert_redirected_to admin_root_path
  end

  test "a wrong password is refused without a session" do
    post admin_login_path, params: { email: @operator.email, password: "wrong" }

    assert_redirected_to admin_login_path
    assert_empty UserSession.live
  end

  test "an ordinary account with the right password is refused exactly like a wrong one" do
    member = create(:user, :admin, :onboarding_completed, password: AuthHelper::TEST_PASSWORD)

    post admin_login_path, params: { email: member.email, password: AuthHelper::TEST_PASSWORD }
    refused_member = session["inertia_errors"]

    post admin_login_path, params: { email: @operator.email, password: "wrong" }
    refused_password = session["inertia_errors"]

    assert_redirected_to admin_login_path
    assert_empty UserSession.live
    assert_predicate refused_member, :present?
    assert_equal refused_password.as_json, refused_member.as_json
  end
end
