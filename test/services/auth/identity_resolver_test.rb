# frozen_string_literal: true

require "test_helper"

module Auth
  class IdentityResolverTest < ActiveSupport::TestCase
    setup do
      @company = create(:company, auto_accept_users: true)
      @google = IdentityProvider.deployment!("google")
      @password = IdentityProvider.password
    end

    def assertion_for(provider, subject:, email:, email_verified: true, name: "Someone")
      Auth::Assertion.new(
        provider: provider, subject: subject, email: email,
        email_verified: email_verified, name: name
      )
    end

    test "resolves by (provider, subject) and ignores a changed email" do
      user = create(:user, company: @company)
      create(:user_identity, user: user, identity_provider: @google, subject: "sub-1")

      resolved = Auth::IdentityResolver.new(
        assertion_for(@google, subject: "sub-1", email: "renamed@#{@company.email_domain}")
      ).resolve

      assert_equal user, resolved
      # One Google identity, not a second one minted for the new address — the
      # factory user also holds a password identity, which is not what this
      # asserts. The identity follows the subject, never the mailbox: a
      # reassigned address must not hand the account to someone else.
      google_identities = user.user_identities.for_kind("google")
      assert_equal 1, google_identities.count
      assert_equal "renamed@#{@company.email_domain}", google_identities.first.reload.email
    end

    test "an unverified email does not promote to an existing user" do
      existing = create(:user, company: @company)

      # Refused by REASON, not by colliding on email uniqueness: the caller can
      # tell the person to sign in the way they already can and link this method
      # afterwards.
      assert_raises(Auth::IdentityResolver::LinkRequiredError) do
        Auth::IdentityResolver.new(
          assertion_for(@google, subject: "sub-unverified", email: existing.email, email_verified: false)
        ).resolve
      end

      assert_equal 0, existing.user_identities.for_kind("google").count
    end

    test "a deployment provider with a verified email promotes to the existing user" do
      existing = create(:user, company: @company)

      resolved = Auth::IdentityResolver.new(
        assertion_for(@google, subject: "sub-promote", email: existing.email)
      ).resolve

      assert_equal existing, resolved
      assert_equal "sub-promote", existing.user_identities.for_kind("google").first.subject
    end

    test "a company provider promotes only inside the domain its owner controls" do
      owner = create(:company, email_domain: "owned-domain.test")
      connection = create(:identity_provider, company: owner, kind: "oidc")
      outsider = create(:user, company: @company)

      # Same verified email, but it belongs to a domain this connection's owner
      # does not control: promotion is refused, and because the address is
      # already taken the caller is told to link rather than shown a collision.
      assert_raises(Auth::IdentityResolver::LinkRequiredError) do
        Auth::IdentityResolver.new(
          assertion_for(connection, subject: "sub-outsider", email: outsider.email)
        ).resolve
      end

      insider = create(:user, email: "insider@owned-domain.test")
      resolved = Auth::IdentityResolver.new(
        assertion_for(connection, subject: "sub-insider", email: insider.email)
      ).resolve

      assert_equal insider, resolved
    end

    test "a super admin may authenticate by password only" do
      super_admin = create(:user, :super_admin)

      error = assert_raises(Auth::IdentityResolver::SuperAdminProviderError) do
        Auth::IdentityResolver.new(
          assertion_for(@google, subject: "sub-admin", email: super_admin.email)
        ).resolve
      end
      assert_match(/password only/, error.message)

      resolved = Auth::IdentityResolver.new(
        assertion_for(@password, subject: super_admin.id.to_s, email: super_admin.email)
      ).resolve
      assert_equal super_admin, resolved
    end

    test "a soft-deleted account resolves but is never linked" do
      deleted = create(:user, company: @company)
      deleted.update!(deleted_at: Time.current)

      resolved = Auth::IdentityResolver.new(
        assertion_for(@google, subject: "sub-deleted", email: deleted.email)
      ).resolve

      assert_equal deleted, resolved
      assert_equal 0, resolved.user_identities.for_kind("google").count
    end

    test "a new user in a matching domain is created and auto-joined" do
      assert_difference "User.count", 1 do
        resolved = Auth::IdentityResolver.new(
          assertion_for(@google, subject: "sub-new", email: "fresh@#{@company.email_domain}")
        ).resolve
        assert_equal @company, resolved.company_memberships.first.company
      end
    end

    test "a new user in an unknown domain raises rather than creating anything" do
      assert_no_difference "User.count" do
        assert_raises(Auth::IdentityResolver::NoWorkspaceError) do
          Auth::IdentityResolver.new(
            assertion_for(@google, subject: "sub-nowhere", email: "ghost@nowhere-#{SecureRandom.hex(3)}.test")
          ).resolve
        end
      end
    end
  end
end
