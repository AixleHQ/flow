# frozen_string_literal: true

require "test_helper"

module Auth
  module Methods
    # Contract test for the generic OIDC adapter: real discovery, token and JWKS
    # payloads over WebMock, and a genuinely signed id_token — the signature path
    # is the whole security value of this adapter, so a fake that skipped it
    # would test nothing.
    class OidcTest < ActiveSupport::TestCase
      ISSUER = "https://idp.example.test"

      setup do
        @company = create(:company, email_domain: "oidc-acme.test")
        @provider = create(:identity_provider, company: @company, kind: "oidc",
                                               config: { "issuer" => ISSUER, "client_id" => "our-client" })
        @provider.client_secret = "our-secret"
        @provider.save!

        @rsa = OpenSSL::PKey::RSA.generate(2048)
        @jwk = JSON::JWK.new(@rsa.public_key, kid: "test-kid")
        # Discovery is cached in production; the test env's :null_store makes
        # every call re-fetch, which the WebMock stubs below allow.

        stub_request(:get, "#{ISSUER}/.well-known/openid-configuration").to_return(
          status: 200, headers: { "Content-Type" => "application/json" },
          body: {
            issuer: ISSUER,
            authorization_endpoint: "#{ISSUER}/authorize",
            token_endpoint: "#{ISSUER}/token",
            jwks_uri: "#{ISSUER}/jwks"
          }.to_json
        )
        stub_request(:get, "#{ISSUER}/jwks").to_return(
          status: 200, headers: { "Content-Type" => "application/json" },
          body: JSON::JWK::Set.new(@jwk).as_json.to_json
        )
      end

      def id_token(claims = {})
        payload = {
          iss: ISSUER, aud: "our-client", sub: "oidc-subject-1",
          exp: 10.minutes.from_now.to_i, iat: Time.current.to_i,
          nonce: "the-nonce", email: "person@oidc-acme.test", email_verified: true,
          name: "OIDC Person"
        }.merge(claims)
        jwt = JSON::JWT.new(payload)
        jwt.kid = "test-kid"
        jwt.sign(@rsa, :RS256).to_s
      end

      def stub_token(token)
        stub_request(:post, "#{ISSUER}/token").to_return(
          status: 200, headers: { "Content-Type" => "application/json" },
          body: { access_token: "at", token_type: "Bearer", id_token: token }.to_json
        )
      end

      def complete(nonce: "the-nonce")
        Auth::Methods::Oidc.new(@provider).complete(
          code: "the-code", redirect_uri: "https://app.test/auth/oidc/callback",
          code_verifier: "verifier", nonce: nonce
        )
      end

      test "the authorize url carries PKCE, the nonce and the connection's client id" do
        url = Auth::Methods::Oidc.new(@provider).authorize_url(
          redirect_uri: "https://app.test/auth/oidc/callback", state: "signed-state",
          code_challenge: "challenge", nonce: "the-nonce"
        )
        query = Rack::Utils.parse_query(URI.parse(url).query)

        assert_equal "#{ISSUER}/authorize", url.split("?").first
        assert_equal "our-client", query["client_id"]
        assert_equal "S256", query["code_challenge_method"]
        assert_equal "challenge", query["code_challenge"]
        assert_equal "the-nonce", query["nonce"]
        assert_equal "signed-state", query["state"]
      end

      test "a valid id_token yields an assertion keyed on sub" do
        stub_token(id_token)

        assertion = complete

        assert_equal "oidc-subject-1", assertion.subject
        assert_equal "person@oidc-acme.test", assertion.email
        assert assertion.email_verified?
      end

      test "an absent email_verified claim is not a true claim" do
        stub_token(id_token(email_verified: nil))

        refute_predicate complete, :email_verified?
      end

      test "an id_token minted for another client is refused" do
        stub_token(id_token(aud: "someone-elses-client"))

        assert_raises(Auth::Method::Failure) { complete }
      end

      test "an id_token from another issuer is refused" do
        stub_token(id_token(iss: "https://evil.example.test"))

        assert_raises(Auth::Method::Failure) { complete }
      end

      test "an id_token replayed from a different login attempt is refused" do
        stub_token(id_token(nonce: "a-different-nonce"))

        assert_raises(Auth::Method::Failure) { complete }
      end

      test "an id_token signed by an unknown key is refused" do
        other = OpenSSL::PKey::RSA.generate(2048)
        jwt = JSON::JWT.new(iss: ISSUER, aud: "our-client", sub: "x",
                            exp: 10.minutes.from_now.to_i, iat: Time.current.to_i, nonce: "the-nonce")
        jwt.kid = "test-kid"
        stub_token(jwt.sign(other, :RS256).to_s)

        assert_raises(Auth::Method::Failure) { complete }
      end

      test "a connection pinned to a tenant refuses an id_token from another one" do
        @provider.update!(config: @provider.config.merge("tenant_id" => "tenant-ours"))
        stub_token(id_token(tid: "tenant-theirs"))

        error = assert_raises(Auth::Method::Failure) { complete }
        assert_match(/does not match this connection/, error.message)
      end

      test "a token endpoint error is a failure, not a silent sign-in" do
        stub_request(:post, "#{ISSUER}/token").to_return(status: 401, body: "nope")

        assert_raises(Auth::Method::Failure) { complete }
      end
    end
  end
end
