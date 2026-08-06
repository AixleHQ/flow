# frozen_string_literal: true

# Unified OAuth 2.1 flow engine (generalizes Web::Integrations::SlackOauthController).
# There is ONE redirect URI per deployment; the provider is carried in the PATH on
# /authorize and in the SIGNED state on /callback, along with all other routing
# data. PKCE is mandatory (OAuth 2.1) and the code_verifier never leaves the server.
#
# Security guards (callback): (1) state signature + 10-min TTL, (2) single-use
# nonce, (3) double user-pinning (signed + cached), (4) mandatory PKCE/S256,
# (5) owner authorization bound to what the current user may act for,
# (6) open-redirect-safe return_to, (7) token-free error logging, (8) cancel
# handled before the nonce is consumed so the user can retry within the TTL.
#
# MCP OAuth (oauth-unification §5): #mcp_connect discovers + dynamically registers
# a client (MCP::OauthDiscoveryService) then runs the same consent flow; the
# callback loads the signed DCR client (constrained to source:"dcr") and threads
# the RFC 8707 resource indicator through the exchange. A DCR token_endpoint is
# attacker-authored, so it is re-validated against the SSRF guard at exchange time.
class Web::OauthController < Web::ApplicationController
  before_action :require_auth, except: :client_metadata
  # The OAuth return must land here even for super-admins (who are otherwise
  # bounced to the admin panel on every web request).
  skip_before_action :redirect_super_admin_to_admin_panel, raise: false

  # GET /oauth/client-metadata.json — public RFC "Client ID Metadata Document".
  # When an MCP authorization server advertises CIMD support, this document's URL
  # is used as our client_id; the AS dereferences it here (no session) to learn our
  # redirect_uris/grant_types. Its `client_id` MUST equal the request URL.
  def client_metadata
    render json: {
      # Built from Settings (NOT the request host) so it is byte-identical to the
      # client_id MCP::OauthDiscoveryService uses — a CIMD document's client_id MUST
      # equal the URL it is served at.
      client_id: "#{Settings.protocol}://#{Settings.domain}/oauth/client-metadata.json",
      client_name: "Aixle Flow",
      redirect_uris: [ redirect_uri ],
      grant_types: %w[authorization_code refresh_token],
      response_types: %w[code],
      token_endpoint_auth_method: "none"
    }
  end

  # GET /oauth/:provider/authorize?owner_type=&owner_id=&mcp_server_id=&return_to=
  def authorize
    provider = params[:provider].to_s
    return redirect_to(root_path, alert: "Unknown OAuth provider") unless Oauth::Providers.known?(provider)

    owner = resolve_owner(params[:owner_type], params[:owner_id])
    return redirect_to(root_path, alert: "Not permitted") if owner.nil?

    client = Oauth::Providers.client_for(provider)

    # PKCE (RFC 7636, S256). The verifier stays server-side in the state cache and
    # is never placed in the URL; only its SHA-256 challenge is sent to the provider.
    code_verifier = SecureRandom.urlsafe_base64(64)
    code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)

    state = Oauth::State.encode(
      owner_type: owner.class.name,
      owner_id: owner.id,
      user_id: current_user.id,
      provider: provider,
      mcp_server_id: params[:mcp_server_id].presence,
      return_to: safe_return_to(params[:return_to]),
      code_verifier: code_verifier
    )

    redirect_to authorize_url(client.authorization_endpoint,
                              response_type: "code",
                              client_id: client.client_id,
                              redirect_uri: redirect_uri,
                              scope: client.scopes,
                              prompt: consent_prompt_for(client.scopes),
                              state: state,
                              code_challenge: code_challenge,
                              code_challenge_method: "S256"),
                allow_other_host: true
  rescue Oauth::MissingClientConfig
    redirect_to root_path, alert: "This provider is not configured"
  end

  # GET /oauth/callback?code=&state=  (single deployment-wide redirect URI)
  def callback
    payload = Oauth::State.decode(params[:state])
    # (1) signature + TTL
    return redirect_to(root_path, alert: "Invalid or expired authorization") if payload.nil?
    # (3a) user pinning — signed side
    unless payload["user_id"] == current_user.id
      return redirect_to(root_path, alert: "Authorization did not match your session")
    end

    return_to = safe_return_to(payload["return_to"])
    # (8) cancel: return BEFORE consuming the nonce so a retry within the TTL works.
    return redirect_to(return_to, alert: "Connection was cancelled") if params[:error].present?

    # (2) single use + fetch the server-side PKCE verifier.
    consumed = Oauth::State.consume(payload["nonce"])
    return redirect_to(return_to, alert: "This authorization link was already used") if consumed.nil?
    # (3b) user pinning — cached side (defense in depth)
    unless consumed["user_id"] == current_user.id
      return redirect_to(return_to, alert: "Authorization did not match your session")
    end

    provider = payload["provider"].to_s

    # (5) owner authorization — even though state is signed, re-bind to a record
    # the CURRENT user may act for.
    owner = resolve_owner(payload["owner_type"], payload["owner_id"])
    return redirect_to(root_path, alert: "Not permitted") if owner.nil?

    # Derive the client. Static providers re-materialize from the trusted registry;
    # MCP (DCR) providers load the signed oauth_client_id — trusted because the state
    # is signed, but still CONSTRAINED to source:"dcr" so a static client id can't be
    # smuggled through the mcp: branch.
    if provider.start_with?("mcp:")
      client = OauthClient.where(source: OauthClient::DISCOVERED_SOURCES).find_by(id: payload["oauth_client_id"])
      return redirect_to(return_to, alert: "Unknown OAuth client") if client.nil?
    else
      return redirect_to(return_to, alert: "Unknown OAuth provider") unless Oauth::Providers.known?(provider)

      client = Oauth::Providers.client_for(provider)
    end

    # (4) PKCE verifier supplied to the exchange (mandatory). The RFC 8707 resource
    # indicator (nil for static providers) is threaded through from the signed state.
    resp = exchange_code!(client, code: params[:code].to_s,
                          code_verifier: consumed["code_verifier"], resource: payload["resource"])

    OauthCredential.upsert_from_token!(
      owner: owner,
      oauth_client: client,
      provider: provider,
      mcp_server: mcp_server_from(payload),
      token_response: resp
    )
    redirect_to return_to, notice: "Connected"
  rescue Oauth::TokenExchangeError => e
    # (7) never logs tokens or the code — only class name / HTTP status.
    Rails.logger.warn("[Oauth] token exchange failed: #{e.message}")
    redirect_to safe_return_to(payload&.dig("return_to")), alert: "Failed to complete connection"
  rescue Oauth::MissingClientConfig
    redirect_to safe_return_to(payload&.dig("return_to")), alert: "This provider is not configured"
  end

  # GET /oauth/mcp/:mcp_server_id/connect?return_to=
  # MCP OAuth 2.1 connect (oauth-unification §5). Mirrors #authorize, but the client
  # is discovered + dynamically registered (DCR) via MCP::OauthDiscoveryService
  # instead of read from the static registry. The RFC 8707 resource indicator (the
  # canonical MCP URL) is threaded into the state so it flows through the exchange
  # and every later refresh. PKCE + `state` handling live ONLY here (never in the
  # discovery service), so the security core stays in one place.
  def mcp_connect
    server = MCPServer.find_by(id: params[:mcp_server_id])
    # Availability + owner authorization: the server must exist, be an OAuth server,
    # and be one the CURRENT user may act for (reuses the Phase-1 owner guard).
    unless server&.auth_type_oauth? && resolve_owner(server.scope_type, server.scope_id)
      return redirect_to(root_path, alert: "Not permitted")
    end

    # Discovery + DCR. Every URL touched here is validated by the SSRF guard inside
    # the service; any failure (incl. an unsafe URL) raises MCP::DiscoveryError.
    result = MCP::OauthDiscoveryService.prepare(mcp_url: server.url)

    # credential_scope decides WHOSE identity connects: per_user => the acting user;
    # shared => the server's scope owner (shared service identity for the tenant).
    owner = server.credential_scope_per_user? ? current_user : server.scope

    # PKCE (RFC 7636, S256). The verifier stays server-side in the state cache.
    code_verifier = SecureRandom.urlsafe_base64(64)
    code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)

    provider = "mcp:#{URI(server.url).host}"
    state = Oauth::State.encode(
      owner_type: owner.class.name,
      owner_id: owner.id,
      user_id: current_user.id,
      provider: provider,
      mcp_server_id: server.id,
      return_to: safe_return_to(params[:return_to]),
      code_verifier: code_verifier,
      resource: result.resource,
      oauth_client_id: result.oauth_client.id
    )

    scope = result.scopes || result.oauth_client.scopes

    redirect_to authorize_url(result.oauth_client.authorization_endpoint,
                              response_type: "code",
                              client_id: result.oauth_client.client_id,
                              redirect_uri: redirect_uri,
                              scope: scope,
                              prompt: consent_prompt_for(scope),
                              resource: result.resource, # RFC 8707 resource indicator
                              state: state,
                              code_challenge: code_challenge,
                              code_challenge_method: "S256"),
                allow_other_host: true
  rescue MCP::DiscoveryError => e
    # (7) token-free logging: class + server id only, never discovered metadata.
    Rails.logger.warn("[Oauth] MCP discovery failed for server=#{params[:mcp_server_id]}: #{e.class.name}")
    redirect_to safe_return_to(params[:return_to]), alert: "Couldn't connect to this MCP server"
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end

  def redirect_uri
    "#{Settings.protocol}://#{Settings.domain}/oauth/callback"
  end

  # Build the consent URL by MERGING our parameters into whatever query the
  # authorization_endpoint already carries — never by concatenating "?#{query}".
  #
  # An authorization_endpoint is allowed to ship with its own query string, and
  # discovered ones do: Railway's RFC 8414 metadata advertises
  # `https://backboard.railway.com/oauth/auth?resource=https%3A%2F%2Fbackboard.railway.com`.
  # Appending a second "?" makes everything up to the first "&" part of the
  # PRECEDING parameter's value, so `response_type=code` was swallowed into
  # `resource` and Railway bounced the user straight back to /oauth/callback with
  # `error=invalid_request&error_description=missing required parameter 'response_type'`
  # — which the callback reports as "Connection was cancelled".
  #
  # Our values win on conflict: the endpoint's baked-in `resource` names the
  # authorization server itself, while RFC 8707 requires the resource indicator to
  # name the MCP server we want the token audience bound to. Our blank values are
  # dropped BEFORE the merge — both so nothing is sent as `scope=` (an empty scope
  # is a request error at some authorization servers) and so a parameter we are not
  # supplying leaves whatever the endpoint carries for it intact.
  def authorize_url(endpoint, params)
    uri = URI.parse(endpoint)
    existing = URI.decode_www_form(uri.query.to_s).to_h
    ours = params.stringify_keys.reject { |_k, v| v.blank? }
    uri.query = URI.encode_www_form(existing.merge(ours))
    uri.to_s
  end

  # `prompt=consent` for an authorization request that asks for `offline_access`,
  # and only then.
  #
  # OIDC Core §11 says an authorization server MUST ignore an `offline_access`
  # request unless it obtains explicit consent, so asking for the scope without
  # `prompt=consent` yields a token set with NO refresh_token — silently, since the
  # granted `scope` simply comes back missing that one entry. Railway's OIDC
  # provider behaves exactly this way (its docs require the pair): the MCP
  # credential then had nothing to refresh from, `OauthCredential.refresh_due`
  # skipped it for want of a refresh_token, and the connection reverted to a
  # Connect button every time the 1-hour access token lapsed.
  #
  # Gated on the requested scope so a plain OAuth 2.1 server, which has no notion
  # of `prompt`, is never sent an OIDC-only parameter.
  def consent_prompt_for(scope)
    "consent" if scope.to_s.split.include?("offline_access")
  end

  # Open-redirect guard: accept only same-site absolute paths ("/..."). Rejects
  # protocol-relative ("//host") and backslash-normalization ("/\\host") tricks
  # that browsers may treat as cross-site, absolute URLs, and blank input.
  # Defaults to root_path.
  def safe_return_to(raw)
    s = raw.to_s
    return root_path if s.blank?
    # Control chars (Tab/CR/LF/…) are stripped by browsers, turning "/\t/evil.com"
    # into a protocol-relative "//evil.com" cross-site redirect — reject them.
    return root_path if s.match?(/[[:cntrl:]]/)
    return root_path unless s.start_with?("/")
    return root_path if s.start_with?("//", "/\\")

    s
  end

  # Bind the owner ONLY to a record the current user may act for:
  #   User    => must be current_user
  #   Company => any company the user is an ACTIVE member of
  #   Project => any project the user can access (Project.for_user)
  # Returns nil when not permitted. The signed state is trusted for routing, but
  # the owner is still authorized against the live session (defense in depth).
  def resolve_owner(owner_type, owner_id)
    case owner_type.to_s
    when "User"
      current_user if owner_id.to_i == current_user.id
    when "Company"
      # Deliberately NOT the session's current company: the signed state may
      # name any company the user belongs to. An invited/suspended/revoked
      # membership must never bind a credential to that tenant.
      current_user.company_memberships.active.find_by(company_id: owner_id)&.company
    when "Project"
      Project.for_user(current_user).find_by(id: owner_id)
    end
  end

  # Bind an MCP server reference ONLY when the current user may act for that
  # server's scope (Company/Project). The signed state is trusted for routing, but
  # an mcp_server_id from a phishing authorize link must never bind a credential to
  # another tenant's server (cross-tenant confused deputy).
  def mcp_server_from(payload)
    id = payload["mcp_server_id"]
    return nil if id.blank?

    server = MCPServer.find_by(id: id)
    return nil unless server && resolve_owner(server.scope_type, server.scope_id)

    server
  end

  # POST token_endpoint as application/x-www-form-urlencoded (client_secret_post).
  # Returns the parsed JSON hash (string keys). Raises Oauth::TokenExchangeError on
  # any non-2xx response, network error, or unparseable body. NEVER interpolates
  # the code or any token into logs or exception messages. When present, the RFC
  # 8707 `resource` indicator (canonical MCP URL) is bound to the exchange.
  def exchange_code!(client, code:, code_verifier:, resource: nil)
    # SECURITY (oauth-unification §5): a source:"dcr" token_endpoint is
    # attacker-authored (discovered from an untrusted MCP server). Re-validate at
    # time-of-use — a persisted endpoint is no more trustworthy than a freshly
    # discovered one (TOCTOU). Static endpoints come from the trusted registry.
    guard_token_endpoint!(client)

    body = {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri,
      code_verifier: code_verifier,
      client_id: client.client_id
    }
    body[:client_secret] = client.client_secret if client.confidential?
    body[:resource] = resource if resource.present?

    uri = URI.parse(client.token_endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    req = Net::HTTP::Post.new(uri)
    req["Accept"] = "application/json"
    req.set_form_data(body)
    res = http.request(req)
    raise Oauth::TokenExchangeError, "status=#{res.code}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  rescue JSON::ParserError, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Oauth::TokenExchangeError, e.class.name
  end

  # Re-validate the token endpoint before an exchange POST. A DCR client's
  # token_endpoint was discovered from an untrusted MCP server, so it must clear
  # the SSRF guard (https + not a private/loopback/link-local host, or a host that
  # resolves to one) at time-of-use — not merely when it was persisted. Static
  # endpoints come from the trusted registry and pass unchanged. Raises
  # Oauth::TokenExchangeError (no endpoint interpolated) so the callback surfaces a
  # generic failure and never contacts the unsafe host.
  def guard_token_endpoint!(client)
    errs = UrlSafetyValidator.errors_for(client.token_endpoint, require_https: true)
    raise Oauth::TokenExchangeError, "unsafe token_endpoint" if errs.any?
  end
end
