# frozen_string_literal: true

require "test_helper"

class GoogleOmniAuthServiceTest < ActiveSupport::TestCase
  def auth_hash(email:, name: "OAuth User", uid: "google-uid-1", image: "https://example.com/avatar.png")
    OmniAuth::AuthHash.new(
      provider: "google",
      uid: uid,
      info: { email: email, name: name, image: image },
      credentials: { token: "mock-token", refresh_token: "mock-refresh-token" }
    )
  end

  test "fresh domain user joins an auto-accept company with an ACTIVE membership" do
    company = create(:company, :auto_accept, email_domain: "acme-auto.io")

    user = GoogleOmniAuthService.new(auth_hash(email: "new@acme-auto.io")).authenticate

    assert user.persisted?
    membership = user.company_memberships.sole
    assert_equal company, membership.company
    assert membership.active?
    assert membership.accepted_at.present?
    assert_equal "employee", membership.role
  end

  test "fresh domain user joins an approval-required company with an INVITED membership" do
    company = create(:company, email_domain: "acme-gated.io") # auto_accept_users: false

    user = GoogleOmniAuthService.new(auth_hash(email: "new@acme-gated.io")).authenticate

    membership = user.company_memberships.sole
    assert_equal company, membership.company
    assert membership.invited?
    assert_nil membership.accepted_at
  end

  test "a user with an existing membership of ANY state is never domain-auto-joined" do
    inviting_company = create(:company)
    domain_company = create(:company, :auto_accept, email_domain: "acme-auto.io")
    invitee = User.create!(email: "invited@acme-auto.io", name: "Invited Externally")
    create(:company_membership, :invited, user: invitee, company: inviting_company)

    user = GoogleOmniAuthService.new(auth_hash(email: "invited@acme-auto.io")).authenticate

    assert_equal invitee.id, user.id
    assert_equal 1, user.company_memberships.count
    assert_not user.company_memberships.exists?(company_id: domain_company.id)
  end

  test "unknown email domain raises NoWorkspaceError without persisting a user" do
    assert_raises(GoogleOmniAuthService::NoWorkspaceError) do
      GoogleOmniAuthService.new(auth_hash(email: "solo@nowhere-known.dev")).authenticate
    end

    assert_nil User.find_by(email: "solo@nowhere-known.dev")
  end

  test "existing user identity is updated (uid/avatar), never duplicated" do
    existing = create(:user, email: "known@example.com")

    user = GoogleOmniAuthService.new(auth_hash(email: "known@example.com", uid: "fresh-uid")).authenticate

    assert_equal existing.id, user.id
    assert_equal "fresh-uid", user.uid
    assert_equal "https://example.com/avatar.png", user.avatar_url
  end

  test "persists a nil avatar when the auth hash omits it" do
    company = create(:company, :auto_accept)

    user = GoogleOmniAuthService.new(
      auth_hash(email: "minimal@#{company.email_domain}", uid: "google-uid-minimal", image: nil)
    ).authenticate

    assert user.persisted?, user.errors.full_messages.to_sentence
    assert_nil user.avatar_url
  end
end
