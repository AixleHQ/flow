# frozen_string_literal: true

require "test_helper"

class Web::InvitationsControllerTest < ActionDispatch::IntegrationTest
  include OmniAuthHelper

  setup do
    @company = create(:company)
    @admin = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
  end

  def invite(user, role: "employee")
    membership = create(:company_membership, :invited, user: user, company: @company,
                                                       role: role, invited_by: @admin)
    [ membership, membership.generate_token_for(:invitation) ]
  end

  # Onboarding is per company, so "completed" means completed FOR THAT COMPANY —
  # including its own agent credential, which is never shared across companies.
  def complete_onboarding_in(user, company)
    membership = user.company_memberships.find_by(company: company) ||
                 create(:company_membership, :invited, user: user, company: company, invited_by: @admin)
    membership.update!(onboarding_state: "completed", onboarding_completed_at: Time.current,
                       position: "dev", preferred_agent_language: "en")
    create(:agent_credential, user: user, company: company, agent_type: "claude_code")
    membership
  end

  # Invited User row created via members#create is passwordless (no OAuth either).
  def passwordless_invitee(email: "fresh@external.com")
    User.create!(email: email, name: "Fresh Invitee")
  end

  # === signup variant (new passwordless user) ===

  test "show renders the signup variant for a passwordless invitee" do
    _membership, token = invite(passwordless_invitee)

    get invitation_path(token)
    assert_inertia_page "Invitations/Show"
    assert_inertia_props variant: "signup", invitedEmail: "fresh@external.com"
  end

  test "signup end-to-end: sets password, activates membership, signs in and redirects to onboarding" do
    invitee = passwordless_invitee
    membership, token = invite(invitee, role: "viewer")

    post signup_invitation_path(token), params: {
      name: "Fresh Invitee", password: "Password1!", password_confirmation: "Password1!"
    }

    assert_redirected_to onboarding_path
    assert membership.reload.active?
    assert membership.accepted_at.present?
    assert invitee.reload.authenticate("Password1!")

    # Signed in: onboarding is reachable without logging in again.
    get onboarding_path
    assert_response :success
  end

  test "AC2: an accepted admin invite grants admin permissions in the inviting company" do
    invitee = passwordless_invitee
    membership, token = invite(invitee, role: "admin")

    post signup_invitation_path(token), params: {
      name: "Fresh Invitee", password: "Password1!", password_confirmation: "Password1!"
    }

    assert membership.reload.active?
    assert_equal "admin", membership.role
    assert_equal 1, invitee.reload.company_memberships.count

    # The permissions shared props live on company screens — complete
    # onboarding so the projects page renders for the fresh account.
    complete_onboarding_in(invitee, @company)
    get company_projects_path
    assert_response :success
    assert_inertia_props do |props|
      props[:permissions][:isAdmin] == true &&
        props[:currentUser][:currentCompany][:id] == @company.id
    end
  end

  test "signup rejects a blank or mismatched password without accepting" do
    membership, token = invite(passwordless_invitee)

    post signup_invitation_path(token), params: { password: "", password_confirmation: "" }
    assert_redirected_to invitation_path(token)
    assert membership.reload.invited?

    post signup_invitation_path(token), params: { password: "Password1!", password_confirmation: "other" }
    assert_redirected_to invitation_path(token)
    assert membership.reload.invited?
  end

  test "signup is refused when the invitee already has credentials" do
    invitee = create(:user, password: AuthHelper::TEST_PASSWORD)
    membership, token = invite(invitee)

    post signup_invitation_path(token), params: {
      password: "Newpass1!", password_confirmation: "Newpass1!"
    }

    assert_redirected_to invitation_path(token)
    assert membership.reload.invited?
  end

  # === Google continuation (passwordless invitee picks OAuth instead) ===

  test "signup variant parks the token and the Google callback accepts the invitation" do
    invitee = passwordless_invitee(email: "fresh@external.com")
    membership, token = invite(invitee)
    complete_onboarding_in(invitee, @company)

    get invitation_path(token)
    assert_inertia_props variant: "signup"

    with_mocked_google_auth(email: "fresh@external.com", name: "Fresh Invitee") do
      get OmniAuthHelper::GOOGLE_CALLBACK_PATH
    end

    assert_redirected_to onboarding_path
    assert membership.reload.active?
    assert_equal 1, invitee.reload.company_memberships.count

    # Signed in, and the inviting company is the current one.
    get company_projects_path
    assert_response :success
    assert_inertia_props do |props|
      props[:currentUser][:currentCompany][:id] == @company.id
    end
  end

  test "an invited external user is never domain-auto-joined into another company via Google" do
    other_company = create(:company, :auto_accept, email_domain: "otherdomain.com")
    invitee = passwordless_invitee(email: "person@otherdomain.com")
    membership, token = invite(invitee)

    get invitation_path(token)

    with_mocked_google_auth(email: "person@otherdomain.com") do
      get OmniAuthHelper::GOOGLE_CALLBACK_PATH
    end

    # The pending invitation wins: it is accepted, and NO membership is
    # created in the domain-matching company.
    assert membership.reload.active?
    memberships = invitee.reload.company_memberships
    assert_equal 1, memberships.count
    assert_not memberships.exists?(company_id: other_company.id)
  end

  # === login variant (existing credentials) + continuation through sessions#create ===

  test "login variant parks the token and sign-in auto-accepts into the inviting company" do
    invitee = create(:user, :onboarding_completed, :with_agent_credential, password: AuthHelper::TEST_PASSWORD)
    membership, token = invite(invitee)
    # Onboarding is per company: pre-complete it for the INVITING company so this
    # test measures the login-continuation, not the new company's onboarding.
    complete_onboarding_in(invitee, @company)

    get invitation_path(token)
    assert_inertia_props variant: "login", invitedEmail: invitee.email

    sign_in_as(invitee)
    assert_redirected_to company_projects_path

    assert membership.reload.active?

    # The inviting company is the current one on the next request.
    get company_projects_path
    assert_response :success
    assert_inertia_props do |props|
      props[:currentUser][:currentCompany][:id] == @company.id
    end
  end

  test "a parked token is dropped when a different user logs in" do
    invitee = create(:user, :onboarding_completed, password: AuthHelper::TEST_PASSWORD)
    other = create(:user, :employee, :onboarding_completed, company: create(:company), password: AuthHelper::TEST_PASSWORD)
    membership, token = invite(invitee)

    get invitation_path(token)
    sign_in_as(other)

    assert membership.reload.invited?
  end

  # === accept variant (signed-in invitee) ===

  test "signed-in invitee sees the accept variant and accepts one-click" do
    # :with_agent_credential keeps this a realistic completed employee —
    # can_complete_onboarding? requires an agent for non-viewers, and without one
    # accepting would (correctly) re-open onboarding instead of landing in the app.
    invitee = create(:user, :employee, :onboarding_completed, :with_agent_credential,
                     company: create(:company), password: AuthHelper::TEST_PASSWORD)
    membership, token = invite(invitee, role: "admin")
    complete_onboarding_in(invitee, @company)
    sign_in_as(invitee)

    get invitation_path(token)
    assert_inertia_props variant: "accept", role: "admin"

    post accept_invitation_path(token)
    assert_redirected_to company_projects_path
    assert membership.reload.active?

    get company_projects_path
    assert_inertia_props do |props|
      props[:currentUser][:currentCompany][:id] == @company.id
    end
  end

  test "decline revokes the membership" do
    invitee = create(:user, :employee, :onboarding_completed, company: create(:company), password: AuthHelper::TEST_PASSWORD)
    membership, token = invite(invitee)
    sign_in_as(invitee)

    post decline_invitation_path(token)
    assert_response :redirect
    assert membership.reload.revoked?
  end

  # === wrong account ===

  test "signed in as a different user shows wrong_account and never accepts" do
    invitee = create(:user, email: "invitee@external.com", password: AuthHelper::TEST_PASSWORD)
    other = create(:user, :employee, :onboarding_completed, company: create(:company), password: AuthHelper::TEST_PASSWORD)
    membership, token = invite(invitee)
    sign_in_as(other)

    get invitation_path(token)
    assert_inertia_props variant: "wrong_account", invitedEmail: "i***@external.com", currentEmail: other.email
    assert membership.reload.invited?
  end

  test "accept as a mismatched signed-in user is rejected" do
    invitee = create(:user, password: AuthHelper::TEST_PASSWORD)
    other = create(:user, :employee, :onboarding_completed, company: create(:company), password: AuthHelper::TEST_PASSWORD)
    membership, token = invite(invitee)
    sign_in_as(other)

    post accept_invitation_path(token)
    assert_redirected_to invitation_path(token)
    assert membership.reload.invited?
    assert_not other.company_memberships.exists?(company_id: @company.id)
  end

  test "accepting twice (double click / two tabs) degrades gracefully instead of raising" do
    invitee = create(:user, :employee, :onboarding_completed, :with_agent_credential,
                     company: create(:company), password: AuthHelper::TEST_PASSWORD)
    membership, token = invite(invitee)
    complete_onboarding_in(invitee, @company)
    sign_in_as(invitee)

    post accept_invitation_path(token)
    assert_redirected_to company_projects_path
    assert membership.reload.active?

    # The token now embeds a stale state — the second POST redirects to the
    # invitation page (which renders "expired"), never 500s.
    post accept_invitation_path(token)
    assert_redirected_to invitation_path(token)
    assert membership.reload.active?
  end

  # === expired / invalid token ===

  test "an invalid token renders the expired variant" do
    get invitation_path("garbage-token")
    assert_inertia_props variant: "expired"
  end

  test "an outdated token (7-day expiry) renders the expired variant" do
    _membership, token = invite(passwordless_invitee)

    travel 8.days do
      get invitation_path(token)
      assert_inertia_props variant: "expired"
    end
  end

  test "a token is dead after the membership was revoked" do
    membership, token = invite(passwordless_invitee)
    membership.revoke!

    get invitation_path(token)
    assert_inertia_props variant: "expired"
  end

  # === re-onboarding on joining a company that needs setup ===
  # A viewer everywhere skips the agent steps and onboarding never re-runs. If a
  # later invitation gives them a role that CAN run things, they would otherwise
  # land on empty agent pickers with no way back into the flow.

  test "accepting an invite runs the NEW company's own onboarding from step1" do
    joiner = create(:user, :employee, :onboarding_completed, :with_agent_credential,
                    company: create(:company), password: AuthHelper::TEST_PASSWORD)
    new_company = create(:company)
    membership = create(:company_membership, :invited, user: joiner, company: new_company,
                                             invited_by: @admin)
    sign_in_as(joiner)

    post accept_invitation_path(membership.generate_token_for(:invitation))

    # Onboarding is per company: being done elsewhere says nothing here, and the
    # agent credential for the other company cannot be reused (billing).
    assert_redirected_to onboarding_path
    assert_equal "step1", membership.reload.onboarding_state
    get onboarding_path
    assert_response :success
  end

  test "accepting an invite lands in the app when that company's onboarding is already done" do
    member = create(:user, :employee, :onboarding_completed, :with_agent_credential,
                    company: create(:company), password: AuthHelper::TEST_PASSWORD)
    target = create(:company)
    membership = create(:company_membership, :invited, user: member, company: target,
                                             invited_by: @admin)
    # Pre-completed for the target company, with its own credential.
    membership.update!(onboarding_state: "completed", onboarding_completed_at: Time.current,
                       position: "dev", preferred_agent_language: "en")
    create(:agent_credential, user: member, company: target, agent_type: "claude_code")
    sign_in_as(member)

    post accept_invitation_path(membership.generate_token_for(:invitation))

    assert_redirected_to company_projects_path
    assert_equal "completed", membership.reload.onboarding_state
  end

  # A viewer needs no agent, but still has to answer that company's step1/step2.
  test "a viewer invite also runs the new company's onboarding" do
    viewer = create(:user, :viewer, :onboarding_completed, company: create(:company),
                                    password: AuthHelper::TEST_PASSWORD)
    membership = create(:company_membership, :invited, :viewer, user: viewer,
                                             company: create(:company), invited_by: @admin)
    sign_in_as(viewer)

    post accept_invitation_path(membership.generate_token_for(:invitation))

    assert_redirected_to onboarding_path
    assert_equal "step1", membership.reload.onboarding_state
  end
end
