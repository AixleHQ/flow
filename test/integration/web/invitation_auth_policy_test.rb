# frozen_string_literal: true

require "test_helper"

# AD-11.2 and AD-12: accepting an invitation is entering a company, so the
# company's policy governs which credential kind may be minted — and "has
# credentials" is a question about identities, never about a password column.
class Web::InvitationAuthPolicyTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @password = IdentityProvider.password
    @inviter = create(:user, company: @company, membership_role: "admin")
    @invitee = create(:user, company: @company, membership_state: "invited", password: nil, password_confirmation: nil)
    @membership = @invitee.company_memberships.find_by(company: @company)
    @token = @membership.generate_token_for(:invitation)
  end

  test "a first-time invitee can set a password when the company accepts passwords" do
    post signup_invitation_path(@token), params: { name: "New Person", password: "TestPassword1!",
                                                   password_confirmation: "TestPassword1!" }

    assert_equal 1, @invitee.reload.user_identities.count
    assert_equal @password.id, @invitee.user_identities.first.identity_provider_id
    assert_equal "active", @membership.reload.state
  end

  test "a company that does not accept passwords does not let an invitation mint one" do
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @password).update!(enabled: false)

    post signup_invitation_path(@token), params: { name: "New Person", password: "TestPassword1!",
                                                   password_confirmation: "TestPassword1!" }

    assert_redirected_to invitation_path(@token)
    assert_equal 0, @invitee.reload.user_identities.count
    # The membership is untouched: nothing was accepted on the back of a
    # credential the company never authorised.
    assert_equal "invited", @membership.reload.state
  end

  test "an invitee who already holds an identity is routed to login, not to signup" do
    @invitee.update!(password: "TestPassword1!", password_confirmation: "TestPassword1!")

    post signup_invitation_path(@token), params: { name: "Nope", password: "TestPassword1!",
                                                   password_confirmation: "TestPassword1!" }

    assert_redirected_to invitation_path(@token)
    assert_equal "invited", @membership.reload.state
  end
end
