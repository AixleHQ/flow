# frozen_string_literal: true

require "test_helper"

module Entra
  class FederatedAssertionTest < ActiveSupport::TestCase
    ISSUER = "https://flow.example.com"
    SUBJECT = "aixle:company:5f0c1c8e-3b1a-4c55-9d0e-5f3b6a7c9d10"
    AUDIENCE = "api://AzureADTokenExchange"

    setup do
      @key = OpenSSL::PKey::RSA.generate(2048)
    end

    def assertion(**overrides)
      FederatedAssertion.new(issuer: ISSUER, subject: SUBJECT, audience: AUDIENCE, private_key: @key,
                             key_id: "kid-1", **overrides).to_jwt
    end

    test "carries the issuer, subject and audience the customer's credential names" do
      claims, header = JWT.decode(assertion, @key.public_key, true, algorithm: "RS256", aud: AUDIENCE, verify_aud: true)

      assert_equal ISSUER, claims["iss"]
      assert_equal SUBJECT, claims["sub"]
      assert_equal AUDIENCE, claims["aud"]
      assert_equal "kid-1", header["kid"]
      assert_equal "RS256", header["alg"]
    end

    test "lives for minutes and is never reused" do
      claims, = JWT.decode(assertion, @key.public_key, true, algorithm: "RS256", verify_aud: false)

      assert_equal FederatedAssertion::LIFETIME.to_i, claims["exp"] - claims["nbf"]
      refute_equal JWT.decode(assertion, nil, false).first["jti"], claims["jti"]
    end

    test "has no certificate thumbprint, unlike a client assertion" do
      _, header = JWT.decode(assertion, nil, false)

      assert_not header.key?("x5t")
    end

    test "refuses to sign without a subject" do
      error = assert_raises(FederatedAssertion::InvalidCredential) { assertion(subject: "") }

      assert_match(/subject/, error.message)
    end

    test "refuses a public key, which cannot sign" do
      error = assert_raises(FederatedAssertion::InvalidCredential) { assertion(private_key: @key.public_key) }

      assert_match(/private key/, error.message)
    end
  end
end
