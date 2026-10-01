# frozen_string_literal: true

require "test_helper"

module OmniAuth
  module Strategies
    # Drives a real callback through the strategy: the token request is the one
    # thing it changes, and WebMock pins exactly what Entra receives.
    class MicrosoftTest < ActiveSupport::TestCase
      CLIENT_ID = "22222222-2222-2222-2222-222222222222"
      TOKEN_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
      THUMBPRINT = "05DD58DC67FC0EB0D5A2C9F0A415B817E3CFADB6"

      setup do
        @key = OpenSSL::PKey::RSA.generate(2048)
        stub_request(:post, TOKEN_URL).to_return do |request|
          @token_request = request
          { status: 200, headers: { "Content-Type" => "application/json" },
            body: { token_type: "Bearer", access_token: "opaque", expires_in: 3600, id_token: id_token }.to_json }
        end
      end

      def id_token
        claims = { aud: CLIENT_ID, exp: 1.hour.from_now.to_i, nbf: 1.minute.ago.to_i,
                   oid: "oid-1", tid: "tenant-1", email: "person@example.test" }
        [ { alg: "none" }, claims ].map { |part| Base64.urlsafe_encode64(part.to_json, padding: false) }.join(".") + "."
      end

      def sign_in(**credentials)
        signed_in = ->(env) { [ 200, {}, [ env["omniauth.auth"].uid ] ] }
        strategy = Microsoft.new(signed_in, { client_id: CLIENT_ID, tenant_id: "common", **credentials })
        env = Rack::MockRequest.env_for("/auth/microsoft/callback?code=auth-code&state=expected-state")
        env["rack.session"] = { "omniauth.state" => "expected-state" }
        strategy.call(env)
      end

      def token_form
        URI.decode_www_form(@token_request.body).to_h
      end

      test "a configured key authenticates the app with a certificate assertion, never the secret" do
        status, _headers, body = sign_in(private_key: @key.to_pem, certificate_thumbprint: THUMBPRINT, client_secret: "left-over-secret")

        assert_equal [ 200, "tenant-1oid-1" ], [ status, body.join ]
        assert_nil @token_request.headers["Authorization"]
        assert_nil token_form["client_secret"]
        assert_equal "urn:ietf:params:oauth:client-assertion-type:jwt-bearer", token_form["client_assertion_type"]
        assert_equal [ CLIENT_ID, "auth-code" ], token_form.values_at("client_id", "code")

        claims, header = JWT.decode(token_form["client_assertion"], @key.public_key, true, algorithm: "RS256")
        assert_equal [ TOKEN_URL, CLIENT_ID ], claims.values_at("aud", "iss")
        assert_equal Base64.urlsafe_encode64([ THUMBPRINT ].pack("H*"), padding: false), header["x5t"]
      end

      test "without a key the client secret is used" do
        status, = sign_in(client_secret: "s3cret")

        assert_equal 200, status
        assert_equal "Basic #{Base64.strict_encode64("#{CLIENT_ID}:s3cret")}", @token_request.headers["Authorization"]
        assert_nil token_form["client_assertion"]
      end

      test "an installation offers Microsoft only with a client id and a credential" do
        assert Microsoft.configured?(Config::Options.new(client_id: CLIENT_ID, private_key: "pem"))
        assert Microsoft.configured?(Config::Options.new(client_id: CLIENT_ID, client_secret: "s3cret"))
        assert_not Microsoft.configured?(Config::Options.new(client_id: CLIENT_ID))
        assert_not Microsoft.configured?(Config::Options.new(private_key: "pem"))
        assert_not Microsoft.configured?(nil)
      end
    end
  end
end
