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
class Web::OauthController < Web::ApplicationController
  before_action :require_auth
  # The OAuth return must land here even for super-admins (who are otherwise
  # bounced to the admin panel on every web request).
  skip_before_action :redirect_super_admin_to_admin_panel, raise: false

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

    query = URI.encode_www_form(
      response_type: "code",
      client_id: client.client_id,
      redirect_uri: redirect_uri,
      scope: client.scopes,
      state: state,
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    )
    redirect_to "#{client.authorization_endpoint}?#{query}", allow_other_host: true
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
    return redirect_to(return_to, alert: "Unknown OAuth provider") unless Oauth::Providers.known?(provider)

    # (5) owner authorization — even though state is signed, re-bind to a record
    # the CURRENT user may act for.
    owner = resolve_owner(payload["owner_type"], payload["owner_id"])
    return redirect_to(root_path, alert: "Not permitted") if owner.nil?

    client = Oauth::Providers.client_for(provider)
    # (4) PKCE verifier supplied to the exchange (mandatory).
    resp = exchange_code!(client, code: params[:code].to_s, code_verifier: consumed["code_verifier"])

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

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end

  def redirect_uri
    "#{Settings.protocol}://#{Settings.domain}/oauth/callback"
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
  #   Company => must be the user's own company
  #   Project => any project the user can access (Project.for_user)
  # Returns nil when not permitted. The signed state is trusted for routing, but
  # the owner is still authorized against the live session (defense in depth).
  def resolve_owner(owner_type, owner_id)
    case owner_type.to_s
    when "User"
      current_user if owner_id.to_i == current_user.id
    when "Company"
      current_user.company if current_user.company_id.present? && owner_id.to_i == current_user.company_id
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
  # the code or any token into logs or exception messages.
  def exchange_code!(client, code:, code_verifier:)
    body = {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri,
      code_verifier: code_verifier,
      client_id: client.client_id
    }
    body[:client_secret] = client.client_secret if client.confidential?

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
end
