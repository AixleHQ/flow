# frozen_string_literal: true

module Entra
  # The short-lived JWT a confidential client signs with its registered
  # certificate, in place of a client secret (RFC 7523 private_key_jwt, as Entra
  # implements it). Shared by everything that authenticates as an Entra app:
  # Microsoft sign-in and the Azure DevOps integration.
  #
  # Hand-built rather than pulled from an identity library because the whole
  # thing is ~20 lines of JWT and the alternative is a dependency that must be
  # kept current for one call.
  class ClientAssertion
    class InvalidCredential < StandardError; end

    # Deliberately short: the assertion is exchanged immediately and never
    # stored, so a long life only widens the window if one ever leaks.
    LIFETIME = 5.minutes

    def initialize(client_id:, private_key:, certificate_thumbprint:, token_url:)
      @client_id = client_id
      @private_key = private_key
      @certificate_thumbprint = certificate_thumbprint
      @token_url = token_url
    end

    def to_jwt
      header = {
        alg: "RS256",
        typ: "JWT",
        # Entra identifies WHICH registered certificate signed this by the
        # base64url of the raw SHA-1 thumbprint bytes — not the hex string
        # shown in the portal. Passing the hex through is the classic
        # "AADSTS700027: Client assertion contains an invalid signature".
        x5t: encoded_thumbprint
      }

      now = Time.current.to_i
      claims = {
        # The token endpoint that will receive this assertion, authority
        # segment included.
        aud: @token_url,
        iss: @client_id,
        sub: @client_id,
        jti: SecureRandom.uuid,
        nbf: now,
        exp: now + LIFETIME.to_i,
        iat: now
      }

      signing_input = "#{base64url(header.to_json)}.#{base64url(claims.to_json)}"
      "#{signing_input}.#{base64url(key.sign(OpenSSL::Digest.new('SHA256'), signing_input))}"
    end

    private

    def key
      OpenSSL::PKey::RSA.new(@private_key.to_s)
    rescue OpenSSL::PKey::RSAError => e
      raise InvalidCredential, "private key is not a readable RSA key: #{e.message}"
    end

    def encoded_thumbprint
      hex = @certificate_thumbprint.to_s.delete(": ").strip
      raise InvalidCredential, "certificate thumbprint is not a SHA-1 hex value" unless hex.match?(/\A\h{40}\z/)

      base64url([ hex ].pack("H*"))
    end

    def base64url(bytes)
      Base64.urlsafe_encode64(bytes, padding: false)
    end
  end
end
