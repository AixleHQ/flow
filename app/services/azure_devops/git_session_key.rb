# frozen_string_literal: true

module AzureDevops
  # Per-session bearer for the in-container Git credential helper.
  #
  # Shaped after CloudAuth::SessionKey, and for the same two reasons, both of
  # which rule out the session's `mcp_key`:
  #
  # 1. Reach. `mcp_key` is handed INTO the container as the `X-Session-Key`
  #    header of the `aixle-tools` MCP server entry, so it is a value the
  #    agent-driven process holds and can read out of its own configuration.
  #    Gating credential vending on it would mean gating it on a secret the
  #    model can already see. "Not an LLM-visible tool" would then be true of
  #    the tool list and false of the access boundary.
  # 2. Coupling. `mcp_key` has a disable endpoint (`disable_mcp_token`).
  #    Reusing it would silently tie "MCP access revoked" to "git push stops
  #    working", which is not a relationship anyone would choose deliberately.
  #
  # Derived from the app's key base, never stored: no new column, no new secret
  # at rest, and it rotates with secret_key_base. The container is given the
  # session id and this key; the server recomputes rather than looks up.
  module GitSessionKey
    PURPOSE = "azure-devops-git-credential-vending"

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
