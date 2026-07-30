# frozen_string_literal: true

module CloudAuth
  # Per-session bearer for the in-container credential helper.
  #
  # Derived from the app's key base, never stored: there is no new column and no new
  # secret at rest, and it rotates with secret_key_base. The container is given the
  # session id and this key, and we recompute rather than look up.
  #
  # Deliberately NOT the session's mcp_key. That key already lets its holder act on the
  # platform as the session, and there is an endpoint to disable it
  # (disable_mcp_token) — reusing it would silently couple "MCP access revoked" to
  # "Bedrock stops working". route_token is unusable for the same job because it travels
  # in URLs.
  module SessionKey
    PURPOSE = "cloud-credential-vending"

    module_function

    def generate(session)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{PURPOSE}:#{session.id}")
    end

    def valid?(session, candidate)
      return false if session.nil? || candidate.blank?

      ActiveSupport::SecurityUtils.secure_compare(generate(session), candidate.to_s)
    end

    def secret
      Rails.application.key_generator.generate_key(PURPOSE, 32)
    end
  end
end
