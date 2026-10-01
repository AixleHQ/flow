# frozen_string_literal: true

require "test_helper"

module Entra
  class ClientAssertionTest < ActiveSupport::TestCase
    TOKEN_URL = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
    CLIENT_ID = "11111111-1111-1111-1111-111111111111"
    THUMBPRINT = "3800CC17D6DCBAA86496BBBCE758ECAC755F1B73"

    setup do
      @key = OpenSSL::PKey::RSA.generate(2048)
    end

    def assertion(**overrides)
      ClientAssertion.new(client_id: CLIENT_ID, private_key: @key.to_pem, certificate_thumbprint: THUMBPRINT,
                          token_url: TOKEN_URL, **overrides).to_jwt
    end

    test "is signed by the key and addressed to the token endpoint" do
      claims, header = JWT.decode(assertion, @key.public_key, true, algorithm: "RS256")

      assert_equal TOKEN_URL, claims["aud"]
      assert_equal CLIENT_ID, claims["iss"]
      assert_equal CLIENT_ID, claims["sub"]
      assert_equal ClientAssertion::LIFETIME.to_i, claims["exp"] - claims["nbf"]
      assert_equal "RS256", header["alg"]
    end

    # Entra matches the certificate by the base64url of the raw SHA-1 bytes;
    # the hex form from the portal is rejected as an invalid signature.
    test "names the certificate by the base64url of its raw thumbprint" do
      _, header = JWT.decode(assertion, @key.public_key, true, algorithm: "RS256")

      assert_equal Base64.urlsafe_encode64([ THUMBPRINT ].pack("H*"), padding: false), header["x5t"]
    end

    test "accepts the thumbprint as the portal and openssl print it" do
      expected = JWT.decode(assertion, @key.public_key, true, algorithm: "RS256").last["x5t"]
      colons = THUMBPRINT.downcase.scan(/../).join(":")

      assert_equal expected, JWT.decode(assertion(certificate_thumbprint: colons), @key.public_key, true, algorithm: "RS256").last["x5t"]
    end

    test "a key that is not an RSA key is a credential error" do
      error = assert_raises(ClientAssertion::InvalidCredential) { assertion(private_key: "not a key") }

      assert_match(/private key/, error.message)
    end

    test "a thumbprint that is not SHA-1 hex is a credential error" do
      error = assert_raises(ClientAssertion::InvalidCredential) { assertion(certificate_thumbprint: "05DD58DC") }

      assert_match(/thumbprint/, error.message)
    end
  end
end
