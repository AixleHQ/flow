# frozen_string_literal: true

module GitCredentials
  # Per-session bearer for the in-container git credential helper (GitHub and
  # GitLab). Derived, never stored, rotating with secret_key_base; its own purpose
  # string, so a key minted for this endpoint is useless at the others. Not the
  # session's mcp_key, for the reason AzureDevops::GitSessionKey gives: revoking
  # MCP access must not also stop `git push`.
  module SessionKey
    PURPOSE = "git-credentials"

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
