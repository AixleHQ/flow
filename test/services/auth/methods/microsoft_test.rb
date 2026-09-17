# frozen_string_literal: true

require "test_helper"

module Auth
  module Methods
    class MicrosoftTest < ActiveSupport::TestCase
      setup do
        @provider = IdentityProvider.deployment!("microsoft")
      end

      def auth_hash(oid: "entra-oid-1", tid: "tenant-abc", email: "person@acme.test", name: "Person")
        {
          "uid" => "#{oid}##{tid}",
          "info" => { "email" => email, "name" => name },
          "extra" => { "raw_info" => { "oid" => oid, "tid" => tid, "name" => name } }
        }
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
