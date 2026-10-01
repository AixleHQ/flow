# frozen_string_literal: true

require "test_helper"

module Auth
  class SignInMethodsTest < ActiveSupport::TestCase
    setup do
      @company = create(:company, name: "Acme")
      @user = create(:user, company: @company)
      @google = IdentityProvider.deployment!("google")
      @microsoft = IdentityProvider.deployment!("microsoft")
    end

    def disable(provider, company: @company)
      CompanyAuthPolicy.find_by!(company: company, identity_provider: provider).update!(enabled: false)
    end

    test "offers the redirect providers a company of the person accepts" do
      assert_equal %w[google microsoft], Auth::SignInMethods.linkable_kinds(@user)

      disable(@microsoft)
      assert_equal %w[google], Auth::SignInMethods.linkable_kinds(@user)

      # Another company of theirs that does accept it is reason enough.
      other = create(:company)
      create(:company_membership, user: @user, company: other)
      assert_equal %w[google microsoft], Auth::SignInMethods.linkable_kinds(@user)
    end

    test "offers nothing the installation cannot complete" do
      Settings.auth.stubs(:enabled_kinds).returns("password,google")

      assert_equal %w[google], Auth::SignInMethods.linkable_kinds(@user)
    end

    test "offers a super admin nothing to link" do
      assert_empty Auth::SignInMethods.linkable_kinds(create(:user, :super_admin))
    end

    test "a method its own credential re-creates is not removed from here" do
      password = @user.user_identities.for_kind("password").sole

      assert_match(/managed from its own section/, Auth::SignInMethods.removal_refusal(@user, password))
    end

    test "the last way in cannot be removed" do
      google = create(:user_identity, user: @user, identity_provider: @google)
      @user.user_identities.for_kind("password").destroy_all

      assert_equal "Google is your only way to sign in.", Auth::SignInMethods.removal_refusal(@user, google)
    end

    test "a removal that strands the person in a company names it" do
      google = create(:user_identity, user: @user, identity_provider: @google)
      disable(IdentityProvider.password)

      assert_equal "Google is your only sign-in method that Acme accepts. Link another method it accepts first.",
                   Auth::SignInMethods.removal_refusal(@user, google)

      error = assert_raises(Auth::SignInMethods::RemovalRefused) { Auth::SignInMethods.remove!(@user, google) }
      assert_match(/Acme/, error.message)
      assert UserIdentity.exists?(google.id)
    end

    test "a removal that leaves an accepted method goes through" do
      google = create(:user_identity, user: @user, identity_provider: @google)

      assert_nil Auth::SignInMethods.removal_refusal(@user, google)
      Auth::SignInMethods.remove!(@user, google)

      assert_not UserIdentity.exists?(google.id)
    end
  end
end
