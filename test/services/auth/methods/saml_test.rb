# frozen_string_literal: true

require "test_helper"

module Auth
  module Methods
    # SAML reaches this process only as an OAuth code from the sidecar (AD-8).
    # These tests pin that wire contract — and, above all, that a code minted for
    # one tenant cannot satisfy another company's connection.
    class SamlTest < ActiveSupport::TestCase
      BRIDGE = "https://sso-bridge.test"

      setup do
        Settings.sso_bridge.stubs(:url).returns(BRIDGE)
        Settings.sso_bridge.stubs(:client_secret).returns("bridge-secret")

        @company = create(:company, email_domain: "saml-acme.test")
        @provider = create(:identity_provider, company: @company, kind: "saml", name: "Acme SAML",
                                               config: { "tenant" => "company-acme", "product" => "aixle" })
      end

      def stub_exchange(profile)
        stub_request(:post, "#{BRIDGE}/api/oauth/token").to_return(
          status: 200, headers: { "Content-Type" => "application/json" },
          body: { access_token: "bridge-token", token_type: "Bearer" }.to_json
        )
        stub_request(:get, "#{BRIDGE}/api/oauth/userinfo").to_return(
          status: 200, headers: { "Content-Type" => "application/json" }, body: profile.to_json
        )
      end

      def profile(tenant: "company-acme", product: "aixle")
        {
          id: "saml-subject-1", email: "person@saml-acme.test",
          firstName: "SAML", lastName: "Person",
          requested: { tenant: tenant, product: product }
        }
      end

      def complete
        Auth::Methods::Saml.new(@provider).complete(
          code: "bridge-code", redirect_uri: "https://app.test/auth/oidc/callback"
        )
      end

      test "the authorize url carries the connection's tenant and product" do
        url = Auth::Methods::Saml.new(@provider).authorize_url(
          redirect_uri: "https://app.test/auth/oidc/callback", state: "signed-state"
        )
        query = Rack::Utils.parse_query(URI.parse(url).query)

        assert_equal "#{BRIDGE}/api/oauth/authorize", url.split("?").first
        assert_equal "tenant=company-acme&product=aixle", query["client_id"]
        assert_equal "signed-state", query["state"]
      end

      test "a profile from the bridge becomes an assertion keyed on its stable id" do
        stub_exchange(profile)

        assertion = complete

        assert_equal "saml-subject-1", assertion.subject
        assert_equal "person@saml-acme.test", assertion.email
        assert_equal "SAML Person", assertion.name
        # A customer's own directory owns the addresses it asserts.
        assert assertion.email_verified?
      end

      test "a code minted for another tenant on the same bridge is refused" do
        # One bridge serves every customer, so without this check a code from
        # another company's connection would satisfy this one (AD-13).
        stub_exchange(profile(tenant: "company-someone-else"))

        error = assert_raises(Auth::Method::Failure) { complete }
        assert_match(/does not match this connection/, error.message)
      end

      test "a code for the right tenant but another product is refused" do
        stub_exchange(profile(product: "some-other-product"))

        assert_raises(Auth::Method::Failure) { complete }
      end

      test "a bridge token failure is a refusal, not a silent sign-in" do
        stub_request(:post, "#{BRIDGE}/api/oauth/token").to_return(status: 401, body: "nope")

        assert_raises(Auth::Method::Failure) { complete }
      end

      test "a userinfo failure is a refusal too" do
        stub_request(:post, "#{BRIDGE}/api/oauth/token").to_return(
          status: 200, headers: { "Content-Type" => "application/json" },
          body: { access_token: "t" }.to_json
        )
        stub_request(:get, "#{BRIDGE}/api/oauth/userinfo").to_return(status: 500, body: "boom")

        assert_raises(Auth::Method::Failure) { complete }
      end

      test "no ruby-saml anywhere in this application" do
        # AD-8 is the whole point: five Critical authentication-bypass advisories
        # in fifteen months is not a dependency to carry in the web process.
        lock = Rails.root.join("Gemfile.lock").read

        refute_match(/^\s+ruby-saml /, lock)
        refute_match(/^\s+omniauth-saml /, lock)
      end
    end
  end
end
