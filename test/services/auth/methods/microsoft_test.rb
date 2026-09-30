# frozen_string_literal: true

require "test_helper"

module Auth
  module Methods
    class MicrosoftTest < ActiveSupport::TestCase
      setup do
        @provider = IdentityProvider.deployment!("microsoft")
      end

      # `claims` land in raw_info, as the id_token carries them (upn, xms_edov);
      # `email_claim` is the id_token's own `email`, `email` the strategy's info.
      def auth_hash(oid: "entra-oid-1", tid: "tenant-abc", email: "person@acme.test", name: "Person",
                    email_claim: nil, **claims)
        raw = { "oid" => oid, "tid" => tid, "name" => name, "email" => email_claim }.compact
        {
          "uid" => "#{oid}##{tid}",
          "info" => { "email" => email, "name" => name },
          "extra" => { "raw_info" => raw.merge(claims.transform_keys(&:to_s)) }
        }
      end

      def complete(**)
        Auth::Methods::Microsoft.new(@provider).complete(auth_hash: auth_hash(**))
      end

      test "the subject is the immutable object id, never the address" do
        assertion = Auth::Methods::Microsoft.new(@provider).complete(auth_hash: auth_hash)

        assert_equal "entra-oid-1", assertion.subject
        assert_equal "person@acme.test", assertion.email
      end

      test "no Entra assertion is ever treated as proof of the address (AD-25)" do
        # Entra sends no email_verified claim, and — unlike Google Workspace — a
        # tenant admin can set an arbitrary address on a user without proving
        # they own its domain. Creating a tenant is free. So "a work or school
        # directory" is NOT evidence, and this adapter says so for every tenant:
        # a Microsoft sign-in may create an account, never adopt one.
        work = Auth::Methods::Microsoft.new(@provider).complete(auth_hash: auth_hash)
        personal = Auth::Methods::Microsoft.new(@provider).complete(
          auth_hash: auth_hash(tid: Auth::Methods::Microsoft::PERSONAL_ACCOUNTS_TENANT)
        )

        refute_predicate work, :email_verified?
        refute_predicate personal, :email_verified?
      end

      test "a UPN at the address shows the tenant owns its domain" do
        assertion = complete(upn: "Person@acme.test")

        assert assertion.joinable_by_domain?
        refute_predicate assertion, :email_verified?
      end

      test "xms_edov vouches for the domain of the email claim" do
        assert complete(xms_edov: true, email_claim: "person@acme.test").joinable_by_domain?
      end

      test "an address without domain evidence is not joinable" do
        # rubocop:disable Minitest/RefuteFalse
        assert_equal false, complete.joinable_by_domain?
        assert_equal false, complete(upn: "person@tenant.onmicrosoft.com").joinable_by_domain?
        assert_equal false, complete(email_claim: "person@acme.test", xms_edov: false).joinable_by_domain?
        # xms_edov speaks for the id_token's email claim, not an address taken from elsewhere.
        assert_equal false, complete(xms_edov: true, email_claim: "other@acme.test").joinable_by_domain?
        assert_equal false, complete(tid: Auth::Methods::Microsoft::PERSONAL_ACCOUNTS_TENANT,
                                     upn: "person@acme.test").joinable_by_domain?
        # rubocop:enable Minitest/RefuteFalse
      end

      test "an assertion with no object id is refused" do
        hash = auth_hash
        hash["extra"]["raw_info"].delete("oid")
        hash["uid"] = nil

        assert_raises(Auth::Method::Failure) do
          Auth::Methods::Microsoft.new(@provider).complete(auth_hash: hash)
        end
      end

      test "a company connection refuses an assertion minted for another tenant" do
        # AD-13: a multi-tenant app registration completes sign-in for ANY
        # directory, so the tenant has to be checked against the row it claims.
        company = create(:company)
        connection = create(:identity_provider, company: company, kind: "microsoft",
                                                config: { "tenant_id" => "tenant-ours" })

        error = assert_raises(Auth::Method::Failure) do
          Auth::Methods::Microsoft.new(connection).complete(auth_hash: auth_hash(tid: "tenant-theirs"))
        end
        assert_match(/does not match this connection/, error.message)

        assertion = Auth::Methods::Microsoft.new(connection).complete(auth_hash: auth_hash(tid: "tenant-ours"))
        assert_equal "entra-oid-1", assertion.subject
      end
    end
  end
end
