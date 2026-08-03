# frozen_string_literal: true

require "test_helper"

class Web::SessionsControllerTest < ActionDispatch::IntegrationTest
  include OmniAuthHelper

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

  test "new echoes a valid email param for pre-filling (invitation flow) and drops junk" do
    get login_path(email: "invitee@client.test")
    assert_inertia_props email: "invitee@client.test"

    get login_path(email: "<script>not-an-email</script>")
    assert_inertia_props email: nil
  end

  # === Google OAuth callback (mocked via OmniAuth test mode) ===

  test "omniauth: fresh user in an auto-accept domain gets an active membership and signs in" do
    company = create(:company, :auto_accept, email_domain: "open-doors.io")

    with_mocked_google_auth(email: "new@open-doors.io") do
      get OmniAuthHelper::GOOGLE_CALLBACK_PATH
    end

    assert_redirected_to onboarding_path
    user = User.find_by!(email: "new@open-doors.io")
    membership = user.company_memberships.sole
    assert_equal company, membership.company
    assert membership.active?

    # Signed in: onboarding is reachable.
    get onboarding_path
    assert_response :success
  end

  test "omniauth: fresh user in an approval-required domain is gated and NOT signed in" do
    create(:company, email_domain: "gated-corp.io") # auto_accept_users: false

    with_mocked_google_auth(email: "new@gated-corp.io") do
      get OmniAuthHelper::GOOGLE_CALLBACK_PATH
    end

    assert_redirected_to login_path(error: "pending_approval")
    membership = User.find_by!(email: "new@gated-corp.io").company_memberships.sole
    assert membership.invited?

    # No session was established.
    get company_projects_path
    assert_redirected_to login_path
  end

  test "omniauth: fresh user with an unknown domain is rejected with no_workspace" do
    assert_no_difference "User.count" do
      with_mocked_google_auth(email: "solo@nowhere-known.dev") do
        get OmniAuthHelper::GOOGLE_CALLBACK_PATH
      end
    end

    assert_redirected_to login_path(error: "no_workspace")
  end

  test "omniauth: an existing member is signed in without any new membership" do
    membership_count = -> { @user.company_memberships.count }

    assert_no_difference membership_count do
      with_mocked_google_auth(email: @user.email, name: @user.name) do
        get OmniAuthHelper::GOOGLE_CALLBACK_PATH
      end
    end

    assert_redirected_to onboarding_path
    get company_projects_path
    assert_response :success
  end

  test "failure redirects to login with error" do
    get auth_failure_path(message: "invalid_credentials")
    assert_redirected_to login_path(error: "invalid_credentials")
  end

  test "omniauth with unrecognized domain redirects to login with no_workspace error and creates no user" do
    unknown_domain = "unknowndomain#{SecureRandom.hex(4)}.xyz"
    unknown_email = "test@#{unknown_domain}"

    # No company exists with this domain — GoogleOmniAuthService will raise NoWorkspaceError
    assert_nil Company.find_by(email_domain: unknown_domain)

    auth_hash = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-uid-unknown",
      info: { email: unknown_email, name: "Ghost User" }
    )

    assert_no_difference "User.count" do
      get auth_callback_path(provider: "google_oauth2"),
        env: { "omniauth.auth" => auth_hash }
    end

    assert_redirected_to login_path(error: "no_workspace")
    assert_nil User.find_by(email: unknown_email)
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
  # === active-membership gate on password login ===
  # enforce_onboarding (Web::ApplicationController) runs BEFORE
  # require_active_membership! (Web::Company::ApplicationController), so a
  # membership-less user that reaches sign_in would be walked through the whole
  # onboarding flow and only then signed out. The gate has to be at login.

  test "create refuses a user whose only membership is still invited (approval pending)" do
    company = create(:company, auto_accept_users: false)
    invitee = create(:user, :employee, :onboarding_completed, company: company,
                                       membership_state: "invited",
                                       password: AuthHelper::TEST_PASSWORD)

    post login_path, params: { user: { email: invitee.email, password: AuthHelper::TEST_PASSWORD } }

    assert_redirected_to login_path(error: "pending_approval")
    # Not signed in: the next request must not be treated as authenticated.
    get onboarding_path
    assert_redirected_to login_path
  end

  test "create refuses a user whose memberships were all revoked" do
    revoked = create(:user, :employee, :onboarding_completed, company: @company,
                                       password: AuthHelper::TEST_PASSWORD)
    revoked.company_memberships.each { |m| m.update!(state: "revoked") }

    post login_path, params: { user: { email: revoked.email, password: AuthHelper::TEST_PASSWORD } }

    assert_redirected_to login_path(error: "pending_approval")
  end

  test "create still signs in a super admin, who legitimately has no memberships" do
    super_admin = create(:user, :super_admin, :onboarding_completed, password: AuthHelper::TEST_PASSWORD)

    post login_path, params: { user: { email: super_admin.email, password: AuthHelper::TEST_PASSWORD } }

    assert_response :redirect
    assert_not_equal login_path(error: "pending_approval"), response.location
  end

  test "create accepts a parked invitation before the membership gate runs" do
    company = create(:company)
    invitee = create(:user, :employee, :onboarding_completed, company: company,
                                       membership_state: "invited",
                                       password: AuthHelper::TEST_PASSWORD)
    membership = invitee.company_memberships.sole

    # Visiting the invitation link parks the token in the session.
    get invitation_path(membership.generate_token_for(:invitation))
    post login_path, params: { user: { email: invitee.email, password: AuthHelper::TEST_PASSWORD } }

    # Accepting flipped the membership active, so the gate must NOT fire.
    assert membership.reload.active?
    assert_not_equal login_path(error: "pending_approval"), response.location
  end
end
