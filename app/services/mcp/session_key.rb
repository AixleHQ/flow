# frozen_string_literal: true

module MCP
  # A session's key to the aixle-tools MCP server, handed into its container.
  #
  # Derived, never stored, so reading the database yields no key that acts as a
  # live session. The key names its session ("<id>.<mac>"): the endpoint
  # recomputes the mac instead of looking the value up. It rotates with
  # secret_key_base, like the other per-session keys (CloudAuth::SessionKey).
  module SessionKey
    PURPOSE = "session-mcp"

    module_function

    def generate(session)
      "#{session.id}.#{mac(session.id)}"
    end

    # The session a presented key belongs to, or nil. Says nothing about whether
    # that session may still use it.
    def session_for(candidate)
      id, presented = candidate.to_s.split(".", 2)
      return nil unless id&.match?(/\A\d+\z/) && presented.present?
      return nil unless ActiveSupport::SecurityUtils.secure_compare(mac(id), presented)

      TerminalSession.find_by(id: id)
    end

    def mac(id)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{PURPOSE}:#{id}")
    end

    def secret
      Rails.application.key_generator.generate_key(PURPOSE, 32)
    end
  end
end
