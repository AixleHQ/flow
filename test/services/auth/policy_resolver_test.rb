# frozen_string_literal: true

require "test_helper"

module Auth
  class PolicyResolverTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @password = IdentityProvider.password
      @google = IdentityProvider.deployment!("google")
      @user = create(:user, company: @company)
    end

    def policy_for(provider)
      CompanyAuthPolicy.find_by!(company: @company, identity_provider: provider)
    end

    test "a new company starts with every deployment provider enabled" do
      kinds = Auth::PolicyResolver.allowed_providers(@company).map { |p| p.kind.to_s }

      assert_includes kinds, "password"
      assert_includes kinds, "google"
    end

    test "a disabled policy leaves the effective set" do
      policy_for(@password).update!(enabled: false)

      kinds = Auth::PolicyResolver.allowed_providers(@company).map { |p| p.kind.to_s }

      refute_includes kinds, "password"
      assert_includes kinds, "google"
    end

    test "the deployment allowlist is a ceiling the company cannot raise" do
      # Both policies enabled, but the installation only offers password.
      Settings.auth.stubs(:enabled_kinds).returns("password")

      kinds = Auth::PolicyResolver.allowed_providers(@company).map { |p| p.kind.to_s }

      assert_equal [ "password" ], kinds
    end

    test "a session is satisfied by a proof the company still accepts" do
      user_session = begin
        s = UserSession.start!(user: @user)
        Auth::SessionService.record_proof(s, @password)
        s
      end

      assert Auth::PolicyResolver.satisfied?(company: @company, user_session: user_session, user: @user)
    end

    test "disabling a provider voids its proof on the next read" do
      user_session = begin
        s = UserSession.start!(user: @user)
        Auth::SessionService.record_proof(s, @password)
        s
      end
      policy_for(@password).update!(enabled: false)

      refute Auth::PolicyResolver.satisfied?(company: @company, user_session: user_session, user: @user)
    end

    test "a proof for another company's connection does not satisfy this one" do
      other = create(:company)
      connection = create(:identity_provider, company: other, kind: "oidc")
      create(:company_auth_policy, company: @company, identity_provider: connection, enabled: true)
      user_session = begin
        s = UserSession.start!(user: @user)
        Auth::SessionService.record_proof(s, connection)
        s
      end

      # Even with an enabled policy row, a company-scoped provider owned by a
      # different company never satisfies entry here.
      refute Auth::PolicyResolver.satisfied?(company: @company, user_session: user_session, user: @user)
    end

    test "a super admin bypasses every company policy surface" do
      super_admin = create(:user, :super_admin)
      user_session = begin
        s = UserSession.start!(user: super_admin)
        Auth::SessionService.record_proof(s, @password)
        s
      end
      policy_for(@password).update!(enabled: false)
      policy_for(@google).update!(enabled: false)

      assert Auth::PolicyResolver.satisfied?(
        company: @company, user_session: user_session, user: super_admin
      )
    end

    test "stranded_members names who a prospective policy would lock out" do
      with_password = create(:user, company: @company)

      with_google = create(:user, company: @company)
      create(:user_identity, user: with_google, identity_provider: @google, subject: "google-sub")

      stranded = Auth::PolicyResolver.stranded_members(@company, [ @google.id ])

      assert_includes stranded, with_password
      refute_includes stranded, with_google
    end

    test "a super admin is never counted as stranded" do
      super_admin = create(:user, :super_admin, company: @company)

      stranded = Auth::PolicyResolver.stranded_members(@company, [])

      refute_includes stranded, super_admin
    end
  end
end
