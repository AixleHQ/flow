# frozen_string_literal: true

require "test_helper"

module AzureDevops
  class FederationConfigTest < ActiveSupport::TestCase
    test "is offered when a key is set and the issuer is a public https origin" do
      with_azure_devops_federation_only

      assert_predicate FederationConfig, :enabled?
    end

    test "is not offered without a signing key" do
      with_azure_devops_federation_only(key: nil)

      assert_not FederationConfig.enabled?
    end

    test "is not offered for a key that is not a private RSA key of 2048 bits or more" do
      with_azure_devops_federation_only(key: nil)
      Settings.azure_devops.federation.signing_key = "not a key"
      assert_not FederationConfig.enabled?

      Settings.azure_devops.federation.signing_key = OpenSSL::PKey::RSA.generate(1024).to_pem
      assert_not FederationConfig.enabled?

      Settings.azure_devops.federation.signing_key = AzureDevopsTestHelper::FEDERATION_KEY.public_key.to_pem
      assert_not FederationConfig.enabled?
    end

    test "is not offered for an issuer Entra can never read" do
      [ "http://flow.example.com", "https://localhost", "https://10.0.0.5", "https://flow.example.com/oidc",
        "https://flow.internal" ].each do |issuer|
        with_azure_devops_federation_only(issuer_url: issuer)

        assert_not FederationConfig.enabled?, "#{issuer} must not be offered"
      end
    end

    test "defaults the issuer to this deployment's own origin, without a trailing slash" do
      with_azure_devops_federation_only(issuer_url: "")
      Settings.stubs(:protocol).returns("https")
      Settings.stubs(:domain).returns("flow.example.org")

      assert_equal "https://flow.example.org", FederationConfig.issuer_url

      with_azure_devops_federation_only(issuer_url: "https://flow.example.com/")
      assert_equal "https://flow.example.com", FederationConfig.issuer_url
    end

    # The worked example in RFC 7638 §3.1.
    test "identifies a key by its RFC 7638 thumbprint" do
      n = "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknj" \
          "hMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5" \
          "hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw"
      integer = ->(encoded) { OpenSSL::ASN1::Integer(OpenSSL::BN.new(Base64.urlsafe_decode64(encoded), 2)) }
      key = OpenSSL::PKey::RSA.new(OpenSSL::ASN1::Sequence([ integer.call(n), integer.call("AQAB") ]).to_der)

      assert_equal "NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs", FederationConfig.key_id(key)
    end

    test "publishes the current key and any previous public key, once each" do
      previous = OpenSSL::PKey::RSA.generate(2048)
      with_azure_devops_federation_only(previous_public_keys: [ previous.public_key.to_pem, previous.public_key.to_pem ])

      kids = FederationConfig.jwks[:keys].pluck(:kid)

      assert_equal [ FederationConfig.current_key_id, FederationConfig.key_id(previous) ], kids
      assert_equal "RS256", FederationConfig.jwks[:keys].first[:alg]
    end

    test "publishes no private material" do
      with_azure_devops_federation_only

      keys = FederationConfig.jwks[:keys]

      assert keys.none? { |jwk| (jwk.keys & %i[d p q dp dq qi]).any? }
    end

    test "discovery names the issuer and where its keys are" do
      with_azure_devops_federation_only

      document = FederationConfig.discovery_document

      assert_equal "https://flow.example.com", document[:issuer]
      assert_equal "https://flow.example.com/.well-known/jwks.json", document[:jwks_uri]
      assert_equal [ "RS256" ], document[:id_token_signing_alg_values_supported]
    end
  end
end
