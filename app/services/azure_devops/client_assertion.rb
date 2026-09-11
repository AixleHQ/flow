# frozen_string_literal: true

module AzureDevops
  # The short-lived JWT a confidential client signs with its registered
  # certificate, in place of a client secret (RFC 7523 private_key_jwt, as Entra
  # implements it).
  #
  # Hand-built rather than pulled from an identity library because the whole
  # thing is ~20 lines of JWT and the alternative is a dependency that must be
  # kept current for one call. The parts Entra is strict about, and that are easy
  # to get wrong, are called out inline.
  class ClientAssertion
    # Deliberately short: the assertion is exchanged immediately and never
    # stored, so a long life only widens the window if one ever leaks.
    LIFETIME = 5.minutes

    def initialize(app:, tenant_id:)
      @app = app
      @tenant_id = tenant_id
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
        # Audience is the TENANT-SPECIFIC token endpoint that will receive this
        # assertion. A /common or mismatched audience is rejected.
        aud: "#{AppConfig.login_host}/#{@tenant_id}/oauth2/v2.0/token",
        iss: @app.client_id,
        sub: @app.client_id,
        jti: SecureRandom.uuid,
        nbf: now,
        exp: now + LIFETIME.to_i,
        iat: now
      }

      signing_input = "#{base64url(header.to_json)}.#{base64url(claims.to_json)}"
      "#{signing_input}.#{base64url(private_key.sign(OpenSSL::Digest.new('SHA256'), signing_input))}"
    end

    private

    def private_key
      OpenSSL::PKey::RSA.new(@app.private_key)
    rescue OpenSSL::PKey::RSAError => e
      raise CredentialActionRequired, "Azure DevOps app private key is not a readable RSA key: #{e.message}"
    end

    def encoded_thumbprint
      hex = @app.certificate_thumbprint.to_s.delete(": ").strip
      raise CredentialActionRequired, "Azure DevOps certificate thumbprint is not a SHA-1 hex value" unless hex.match?(/\A\h{40}\z/)

      base64url([ hex ].pack("H*"))
    end

    def base64url(bytes)
      Base64.urlsafe_encode64(bytes, padding: false)
    end
  end
end
