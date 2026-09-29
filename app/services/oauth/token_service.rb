# frozen_string_literal: true

module Oauth
  # On-demand OAuth access-token provisioning (RFC oauth-unification §4.5).
  # Picks the applicable credential, refreshes it under its refresh lease when it
  # is within REFRESH_SKEW of expiry, never clobbers a fresher concurrent token,
  # and returns a usable access token or raises Oauth::ReauthRequired.
  module TokenService
    REFRESH_SKEW = 10.minutes
    # Pre-session refresh window: sized for session duration, not single-request latency.
    # A credential expiring within this window is refreshed before the session starts so
    # the one-shot MCP token injection receives a token valid for the whole session run.
    # Distinct from REFRESH_SKEW, which governs on-demand per-request refreshes.
    PRE_START_SKEW = 1.hour
    # A token endpoint is someone else's server; without a bound, one that never
    # answers holds a refresh lease and a request thread for Net::HTTP's minute.
    TOKEN_TIMEOUT = 15

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

    # Credential selection.
    # - server: scope-driven (oauth-unification §4.4). credential_scope decides the
    #   identity — per_user => the acting `user`; shared => the server's scope owner.
    #   NEVER an owner-blind fallback, which would inject another tenant's token into
    #   this session (cross-tenant confused deputy). For an OAuth server a MISSING
    #   credential is not "no credential attached" — it means the user/scope must
    #   connect, so it raises ReauthRequired to trip the session-start preflight.
    # - owner/provider: newest active credential for that owner+provider (unchanged).
    def pick_credential(server:, owner:, provider:, user:)
      if server
        cred_owner = server.credential_scope_per_user? ? user : server.scope
        return nil if cred_owner.nil? # can't resolve an identity to act as

        cred = OauthCredential.current_for(server: server, owner: cred_owner)
        raise Oauth::ReauthRequired.new(nil, "connect required") if cred.nil? && server.auth_type_oauth?

        cred
      elsif owner && provider
        OauthCredential.for_owner(owner).where(provider: provider)
                       .where.not(status: :revoked).order(updated_at: :desc).first
      end
    end

    # Sweep entry point (Activities::Oauth::RefreshExpiringTokensActivity). Refreshes
    # a due credential through the SAME `fresh` path as on-demand use (refresh-under-
    # lock + rotation guard + failure escalation), reporting an outcome symbol for the
    # activity's counts. :not_needed when the credential wasn't within REFRESH_SKEW yet
    # (a later sweep tick, closer to expiry, will refresh it).
    # @return [Symbol] :refreshed | :not_needed | :error
    def refresh_credential(cred)
      before = cred.access_token
      fresh(cred, wait: false)
      cred.access_token == before ? :not_needed : :refreshed
    rescue Oauth::ReauthRequired
      :error
    end

    # Pre-session token refresh: ensure the credential will not expire within `skew`.
    # Called before session start so the one-shot MCP token injection gets a fresh token
    # with a full TTL. Silently skips non-refreshable credentials (they are caught by the
    # usability preflight earlier).
    # Concurrent calls on the same credential are safe: `fresh` refreshes under the
    # credential's refresh lease, so a racing caller waits for that refresh and uses
    # its token — no stampede even with providers that rotate refresh tokens.
    def refresh_if_expiring_soon(cred, skew: PRE_START_SKEW)
      return unless cred.expired?(skew)
      return unless cred.refreshable?

      fresh(cred, skew: skew)
    rescue ReauthRequired
      # Already caught by preflight — do not re-raise here, session start will
      # surface it through the normal token injection path.
      nil
    end

    # Ensure `cred` yields a fresh token, refreshing it when near expiry.
    #
    # One refresher at a time, and never inside a transaction (RefreshLease): the
    # lease is taken, the provider is called, and the answer is persisted in a
    # transaction of its own — a rolled-back write of a rotated refresh token would
    # lose the only valid one. A caller that finds another refresh under way waits
    # for it and uses its result.
    # `wait: false` (the sweep) leaves a credential another refresher holds to that
    # refresher instead of waiting on it.
    def fresh(cred, skew: REFRESH_SKEW, wait: true)
      return cred.access_token unless cred.expired?(skew)

      # Nothing to refresh from. Record it like any other refresh failure so the
      # credential escalates to status:error (and notifies the owner to reconnect)
      # through the ONE existing path, instead of sitting :active until its access
      # token lapses. The sweep sees these rows too — OauthCredential.refresh_due is
      # not filtered on refresh_token — so escalation does not wait for a session to
      # happen to use the credential.
      unless cred.refreshable?
        cred.mark_refresh_error!("no refresh token — reconnect required")
        raise ReauthRequired.new(cred)
      end

      outcome = cred.with_refresh_lease do
        # A concurrent request may have refreshed just before the lease was ours.
        next unless cred.expired?(skew)

        refresh_leased!(cred)
      end
      if outcome == :busy
        return cred.access_token unless wait

        cred.await_refresh
      end

      raise ReauthRequired.new(cred) if cred.access_token.blank? || cred.expired?(skew)

      cred.access_token
    rescue Encryptable::DecryptionError => e
      cred.mark_refresh_error!(e.message)
      raise ReauthRequired.new(cred, "stored tokens are unreadable")
    end

    def refresh_leased!(cred)
      sent = cred.refresh_token
      resp = perform_refresh!(cred)
      cred.with_lock do
        # Never downgrade: only persist if the new expiry is >= the stored one.
        new_exp = resp["expires_in"].present? ? Time.current + resp["expires_in"].to_i.seconds : nil
        cred.apply_token_response!(resp) if new_exp.nil? || cred.expires_at.nil? || new_exp >= cred.expires_at
      end
    rescue StandardError => e
      # Only a rejection of the refresh token still stored is this credential's
      # failure; one rotated meanwhile (the old token was sent) is not.
      cred.mark_refresh_error!(e.message) if cred.reload.refresh_token == sent
      raise ReauthRequired.new(cred, "refresh failed")
    end

    # POST token_endpoint, form-encoded refresh_token grant + client auth.
    # Returns parsed JSON (string keys). NEVER logs token material.
    def perform_refresh!(cred)
      client = cred.oauth_client
      body = { grant_type: "refresh_token", refresh_token: cred.refresh_token, client_id: client.client_id }
      body[:client_secret] = client.client_secret if client.confidential?

      # SECURITY (oauth-unification §5): a source:"dcr" token_endpoint is
      # attacker-authored — re-validate at time-of-use, since a persisted endpoint is
      # no more trustworthy than a freshly discovered one (TOCTOU). Static endpoints
      # come from the trusted registry and pass. Raised as StandardError so `fresh`
      # marks the credential errored and surfaces ReauthRequired.
      uri_errs = UrlSafetyValidator.errors_for(client.token_endpoint, require_https: true)
      raise "unsafe token_endpoint" if uri_errs.any?

      # RFC 8707 resource indicator: the one the grant was issued for.
      body[:resource] = cred.resource.presence || cred.mcp_server.url if cred.mcp_server_id.present?

      uri = URI.parse(client.token_endpoint)
      http = SafeHttp.http_for(uri, open_timeout: TOKEN_TIMEOUT, read_timeout: TOKEN_TIMEOUT)
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
