# frozen_string_literal: true

require "test_helper"

module Auth
  class PolicyUpdaterTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @password = IdentityProvider.password
      @google = IdentityProvider.deployment!("google")
      # The password identity now appears with the password itself (User
      # after_save -> Auth::LocalCredential), so nothing is seeded by hand here —
      # seeding it was what hid the missing production link in the first place.
      @admin = create(:user, company: @company, membership_role: "admin")
      @updater = Auth::PolicyUpdater.new(company: @company, actor: @admin)
    end

    test "disabling a provider the members do not depend on is allowed" do
      policy = @updater.set(@google, enabled: false)

      refute policy.enabled
      refute_includes Auth::PolicyResolver.allowed_provider_ids(@company), @google.id
    end

    test "a change that would strand a member is refused and names them" do
      error = assert_raises(Auth::PolicyUpdater::Refused) do
        @updater.set(@password, enabled: false)
      end

      assert_equal :would_strand, error.reason
      assert_includes error.stranded, @admin
      # Nothing was written: the guard and the write share one transaction.
      assert_includes Auth::PolicyResolver.allowed_provider_ids(@company), @password.id
    end

    test "deleting a connection is guarded exactly as disabling it" do
      error = assert_raises(Auth::PolicyUpdater::Refused) do
        @updater.remove(@password)
      end

      assert_equal :would_strand, error.reason
      assert CompanyAuthPolicy.exists?(company: @company, identity_provider: @password)
    end

    test "a company connection cannot be enabled before an admin has proved it" do
      connection = create(:identity_provider, company: @company, kind: "oidc")

      error = assert_raises(Auth::PolicyUpdater::Refused) do
        @updater.set(connection, enabled: true)
      end

      assert_equal :not_proved, error.reason
    end

    test "once an admin has signed in through a connection it can be enabled" do
      connection = create(:identity_provider, company: @company, kind: "oidc")
      create(:user_identity, user: @admin, identity_provider: connection, subject: "oidc-sub")

      policy = @updater.set(connection, enabled: true)

      assert policy.enabled
    end

    test "a super admin may override both guards" do
      operator = create(:user, :super_admin)
      updater = Auth::PolicyUpdater.new(company: @company, actor: operator)
      connection = create(:identity_provider, company: @company, kind: "oidc")

      assert updater.set(connection, enabled: true).enabled
      refute updater.set(@password, enabled: false).enabled
    end

    test "an admin cannot disable the method their own live session was proved with" do
      # AD-7 rule 4. Another member holds Google, so nobody is stranded — the
      # only thing this edit breaks is the acting admin's own re-entry.
      other = create(:user, company: @company)
      create(:user_identity, user: other, identity_provider: @google, subject: "google-other")
      create(:user_identity, user: @admin, identity_provider: @google, subject: "google-admin")
      user_session = Auth::SessionService.start(user: @admin, provider: @password).user_session
      updater = Auth::PolicyUpdater.new(company: @company, actor: @admin, user_session: user_session)

      error = assert_raises(Auth::PolicyUpdater::Refused) do
        updater.set(@password, enabled: false)
      end

      assert_equal :would_lock_out_actor, error.reason
    end

    test "the actor guard passes once the admin has proved a method that survives the edit" do
      other = create(:user, company: @company)
      create(:user_identity, user: other, identity_provider: @google, subject: "google-other2")
      create(:user_identity, user: @admin, identity_provider: @google, subject: "google-admin2")
      user_session = Auth::SessionService.start(user: @admin, provider: @password).user_session
      Auth::SessionService.record_proof(user_session, @google)
      updater = Auth::PolicyUpdater.new(company: @company, actor: @admin, user_session: user_session)

      refute updater.set(@password, enabled: false).enabled
    end

    test "setting a policy to the value it already has is a no-op, not a refusal" do
      # The guard must not fire on a change that changes nothing — a UI that
      # re-submits the current state would otherwise be unusable.
      policy = @updater.set(@password, enabled: true)

      assert policy.enabled
    end
  end
end
