# frozen_string_literal: true

module Oauth
  # On-demand OAuth access-token provisioning (RFC oauth-unification §4.5).
  # Picks the applicable credential, refreshes it under `with_lock` when it is
  # within REFRESH_SKEW of expiry, never clobbers a fresher concurrent token,
  # and returns a usable access token or raises Oauth::ReauthRequired.
  module TokenService
    REFRESH_SKEW = 10.minutes

    module_function

    # Return a fresh access token for an MCP server (server:) OR a direct provider
    # (owner: + provider:). Returns nil when NO applicable credential exists
    # (keeps the injection hook a no-op). Raises Oauth::ReauthRequired when a
    # credential exists but is dead/unrefreshable.
    #
    #   access_token_for(server: mcp_server, user: session.user)
    #   access_token_for(owner: company, provider: "sentry", user: current_user)
    def access_token_for(server: nil, owner: nil, provider: nil, user: nil)
      cred = pick_credential(server: server, owner: owner, provider: provider, user: user)
      return nil if cred.nil?

      fresh(cred)
    end

    # Phase-1 credential selection.
    # - server: prefer a live credential owned by `user`, else the server's scope
    #   owner (shared identity). credential_scope enum is Phase 3; until then
    #   presence of a credential row attached to the server IS the trigger.
    # - owner/provider: newest active credential for that owner+provider.
    def pick_credential(server:, owner:, provider:, user:)
      if server
        scope = OauthCredential.for_mcp_server(server).where.not(status: :revoked)
        # Only the user's own credential or the server's scope-owner (shared
        # identity) — NEVER an owner-blind fallback, which would inject another
        # tenant's token into this session (cross-tenant confused deputy).
        (user && scope.for_owner(user).order(updated_at: :desc).first) ||
          (server.scope && scope.for_owner(server.scope).order(updated_at: :desc).first)
      elsif owner && provider
        OauthCredential.for_owner(owner).where(provider: provider)
                       .where.not(status: :revoked).order(updated_at: :desc).first
      end
    end

    # Ensure `cred` yields a fresh token; refresh under lock if near expiry.
    def fresh(cred)
      return cred.access_token unless cred.expired?(REFRESH_SKEW)
      raise ReauthRequired.new(cred) unless cred.refreshable?

      cred.with_lock do
        cred.reload
        # A concurrent request may have refreshed while we waited on the lock.
        break unless cred.expired?(REFRESH_SKEW)

        resp = perform_refresh!(cred)
        # Never downgrade: only persist if the new expiry is >= the stored one.
        new_exp = resp["expires_in"].present? ? Time.current + resp["expires_in"].to_i.seconds : nil
        cred.apply_token_response!(resp) if new_exp.nil? || cred.expires_at.nil? || new_exp >= cred.expires_at
      end

      raise ReauthRequired.new(cred) if cred.access_token.blank? || cred.expired?(REFRESH_SKEW)

      cred.access_token
    rescue ReauthRequired
      raise
    rescue StandardError => e
      cred.mark_refresh_error!(e.message)
      raise ReauthRequired.new(cred, "refresh failed")
    end

    # POST token_endpoint, form-encoded refresh_token grant + client auth.
    # Returns parsed JSON (string keys). NEVER logs token material.
    def perform_refresh!(cred)
      client = cred.oauth_client
      body = { grant_type: "refresh_token", refresh_token: cred.refresh_token, client_id: client.client_id }
      body[:client_secret] = client.client_secret if client.confidential?

      uri = URI.parse(client.token_endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      req = Net::HTTP::Post.new(uri)
      req["Accept"] = "application/json"
      req.set_form_data(body)
      res = http.request(req)
      raise "refresh status=#{res.code}" unless res.is_a?(Net::HTTPSuccess)

      begin
        JSON.parse(res.body)
      rescue JSON::ParserError
        # Never let the raw body (which may echo token material) reach the persisted
        # refresh_error column or logs — surface status only (mirrors exchange_code!).
        raise "refresh response not valid JSON (status=#{res.code})"
      end
    end
  end
end
