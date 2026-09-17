# frozen_string_literal: true

require "test_helper"

# End-to-end coverage for the company-entry auth policy (AD-4, AD-5, AD-6,
# AD-19): a company decides which methods it accepts, the gate enforces that at
# entry rather than at the login screen, and a session that no longer satisfies
# a company is sent to step-up instead of being signed out.
class Web::CompanyAuthPolicyTest < ActionDispatch::IntegrationTest
  include OmniAuthHelper

  setup do
    @company = create(:company, auto_accept_users: true)
    @user = create(:user, :onboarding_completed, company: @company,
                          password: AuthHelper::TEST_PASSWORD,
                          password_confirmation: AuthHelper::TEST_PASSWORD)
    @password = IdentityProvider.password
    @google = IdentityProvider.deployment!("google")
  end

  def policy_for(provider, company: @company)
    CompanyAuthPolicy.find_by!(company: company, identity_provider: provider)
  end

  test "signing in with password leaves a live session carrying a password proof" do
    sign_in_as(@user)

    auth_session = AuthSession.live.find_by(user: @user)
    assert_not_nil auth_session
    assert_equal [ @password.id ], auth_session.proved_provider_ids
  end

  test "signing in with a password creates the identity the policy guard reads" do
    # Regression: the backfill migration only covers passwords that existed when
    # it ran. Without linking on sign-in, anyone who set a password afterwards
    # holds zero identities and PolicyResolver.stranded_members reports them
    # stranded under every prospective policy — refusing even additive edits.
    fresh = create(:user, :onboarding_completed, company: @company,
                          password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    fresh.user_identities.destroy_all

    sign_in_as(fresh)

    assert_equal [ @password.id ], fresh.reload.user_identities.map(&:identity_provider_id)
    refute_includes Auth::PolicyResolver.stranded_members(@company, [ @password.id ]), fresh
  end

  test "a company that stops accepting the proved method sends the user to step-up, not to login" do
    sign_in_as(@user)
    policy_for(@password).update!(enabled: false)

    get company_projects_path

    assert_redirected_to step_up_path
    # Still signed in: the session survives, it simply does not satisfy this
    # company any more.
    assert AuthSession.live.exists?(user: @user)
  end

  test "the step-up page names the methods the company still accepts" do
    sign_in_as(@user)
    policy_for(@password).update!(enabled: false)

    get step_up_path

    assert_response :success
    assert_match "Google", response.body
  end

  test "proving an accepted method at step-up restores entry" do
    sign_in_as(@user)
    # Google is what this company stops accepting; password stays available, so
    # step-up can actually be completed with a password.
    policy_for(@google).update!(enabled: false)
    auth_session = AuthSession.live.find_by(user: @user)
    auth_session.proofs.destroy_all
    Auth::SessionService.append_proof(auth_session, @google)

    get company_projects_path
    assert_redirected_to step_up_path

    post step_up_path, params: { step_up: { password: AuthHelper::TEST_PASSWORD } }

    assert_redirected_to company_projects_path
    assert_includes auth_session.reload.proved_provider_ids, @password.id
  end

  test "a wrong password at step-up is refused without ending the session" do
    sign_in_as(@user)
    auth_session = AuthSession.live.find_by(user: @user)
    auth_session.proofs.destroy_all
    Auth::SessionService.append_proof(auth_session, @google)
    policy_for(@google).update!(enabled: false)

    post step_up_path, params: { step_up: { password: "not-the-password" } }

    assert_redirected_to step_up_path(error: "invalid_credentials")
    assert AuthSession.live.exists?(id: auth_session.id)
  end

  test "proofs append across companies with disjoint policies, so step-up does not ping-pong" do
    other = create(:company, auto_accept_users: true)
    create(:company_membership, user: @user, company: other, state: "active",
                                accepted_at: Time.current, onboarding_state: "completed",
                                onboarding_completed_at: Time.current)
    # This company accepts Google only; the first one accepts password only.
    policy_for(@password, company: other).update!(enabled: false)
    policy_for(@google).update!(enabled: false)

    sign_in_as(@user)
    auth_session = AuthSession.live.find_by(user: @user)

    with_mocked_google_auth(email: @user.email, uid: "google-uid-pingpong") do
      get "/auth/google/callback"
    end

    # ONE session, now carrying both proofs — so both companies are satisfied at
    # the same time and neither bounces the user back to step-up.
    assert_equal 1, AuthSession.live.where(user: @user).count
    assert_equal [ @password.id, @google.id ].sort, auth_session.reload.proved_provider_ids.sort

    assert Auth::PolicyResolver.satisfied?(company: @company, auth_session: auth_session, user: @user)
    assert Auth::PolicyResolver.satisfied?(company: other, auth_session: auth_session, user: @user)
  end

  test "revoking a session ends access on the next request" do
    sign_in_as(@user)
    AuthSession.live.find_by(user: @user).revoke!

    get company_projects_path

    assert_redirected_to login_path
  end

  test "a super admin is admitted whatever the company forbids" do
    super_admin = create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD,
                                              password_confirmation: AuthHelper::TEST_PASSWORD)
    policy_for(@password).update!(enabled: false)
    policy_for(@google).update!(enabled: false)

    sign_in_as(super_admin)

    get admin_root_path

    assert_response :success
  end

  test "a super admin cannot sign in through Google" do
    super_admin = create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD,
                                              password_confirmation: AuthHelper::TEST_PASSWORD)

    with_mocked_google_auth(email: super_admin.email, uid: "google-uid-super") do
      get "/auth/google/callback"
    end

    assert_redirected_to login_path(error: "super_admin_password_only")
    refute AuthSession.live.exists?(user: super_admin)
  end
end
