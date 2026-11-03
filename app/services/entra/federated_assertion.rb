# frozen_string_literal: true

module Entra
  # The short-lived JWT Flow signs as an OIDC issuer, which a customer's Entra app
  # trusts through a federated identity credential ("Other issuer"). Entra checks
  # `iss`, `sub` and `aud` against that credential, fetches the signing key from
  # the issuer's JWKS, and exchanges the assertion for an access token of the
  # customer's app. Unlike ClientAssertion there is no certificate: the app
  # holds no secret at all, and the trust is the credential itself.
  #
  # `aud` is the fixed Entra token-exchange audience, not the token endpoint URL
  # that a certificate assertion carries.
  class FederatedAssertion
    class InvalidCredential < StandardError; end

    # The assertion is exchanged immediately and never stored.
    LIFETIME = 5.minutes

    def initialize(issuer:, subject:, audience:, private_key:, key_id:)
      @issuer = issuer
      @subject = subject
      @audience = audience
      @private_key = private_key
      @key_id = key_id
    end

    def to_jwt
      raise InvalidCredential, "subject is blank" if @subject.blank?
      raise InvalidCredential, "signing key is not an RSA private key" unless @private_key.is_a?(OpenSSL::PKey::RSA) && @private_key.private?

      header = { alg: "RS256", typ: "JWT", kid: @key_id }
      now = Time.current.to_i
      claims = {
        iss: @issuer,
        sub: @subject,
        aud: @audience,
        jti: SecureRandom.uuid,
        nbf: now,
        iat: now,
        exp: now + LIFETIME.to_i
      }

      signing_input = "#{base64url(header.to_json)}.#{base64url(claims.to_json)}"
      "#{signing_input}.#{base64url(@private_key.sign(OpenSSL::Digest.new('SHA256'), signing_input))}"
    end

    private

    def base64url(bytes)
      Base64.urlsafe_encode64(bytes, padding: false)
    end
  end
end
