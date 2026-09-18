# frozen_string_literal: true

module Agents
  # Per-session bearer for the in-container credential write-back.
  #
  # Derived from the app's key base and never stored — no new column, no new secret at
  # rest, and it rotates with secret_key_base. The container is handed the session id and
  # this key; the server recomputes rather than looks up. Same construction as
  # CloudAuth::SessionKey, with its own purpose string so a key minted for one endpoint is
  # useless at the other.
  #
  # Deliberately NOT the session's mcp_key: that key lets its holder act on the platform as
  # the session and can be disabled independently, and coupling "MCP access revoked" to
  # "this session can no longer report its rotated token" would silently reintroduce the
  # lost-rotation problem this endpoint exists to fix.
  module SessionKey
    PURPOSE = "agent-credential-writeback"

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
