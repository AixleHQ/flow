# frozen_string_literal: true

# The Aixle MCP server endpoint for agent containers. Authenticates the
# TerminalSession from its per-session key (X-Session-Key header or
# Authorization bearer; never a query parameter, which lands in ingress logs),
# then serves the request from a stateless per-request MCP::Server
# (Tools::MCPRequestHandler).
class MCPController < ActionController::API
  # The values come from the client and land unescaped in a key=value log line.
  LOGGABLE_NAME = %r{\A[\w./-]{1,128}\z}

  def handle
    handler = resolve_handler
    return unauthorized_response if handler.nil?

    status, headers, body = handler.call(request)
    headers.each { |k, v| response.set_header(k, v) }
    render plain: Array(body).join, status: status
  end

  def append_info_to_payload(payload)
    super
    payload[:user] = @logged_user_id
    payload[:session] = @logged_session_id
    payload.merge!(rpc_log_fields)
  end

  private

  # Rails calls append_info_to_payload in an `ensure` after the tool has run, so
  # a raise here would answer an executed call with a 500 and the agent would
  # repeat its side effects. Logging gives up instead.
  #
  # The body was already parsed for the instrumentation payload. A batch
  # (top-level array) arrives under `_json`, so it logs no method.
  def rpc_log_fields
    message = request.request_parameters
    rpc = loggable_name(message["method"])
    rpc_params = message["params"]
    tool = loggable_name(rpc_params["name"]) if rpc == "tools/call" && rpc_params.is_a?(Hash)
    { rpc: rpc, tool: tool }
  rescue StandardError
    {}
  end

  def loggable_name(value)
    value if value.is_a?(String) && value.match?(LOGGABLE_NAME)
  end

  # Three credentials on one endpoint, split by shape: an amcp_ personal token
  # and an OAuth access token (MCPAuthToken) both serve the user-level server;
  # anything else is a terminal session's mcp_key serving the session-scoped one.
  def resolve_handler
    key = presented_key
    return nil if key.blank?

    if key.start_with?(User::MCP_TOKEN_PREFIX)
      personal_token_handler(key)
    elsif MCPAuthToken.access_token?(key)
      oauth_handler(key)
    else
      session = MCP::SessionKey.lookup(key)
      return nil unless session&.active? && session.owner_entitled?

      @logged_session_id = session.id
      Tools::MCPRequestHandler.new(session)
    end
  end

  def personal_token_handler(key)
    user = User.find_by_mcp_token(key)
    return nil if user.nil?

    user.note_mcp_token_use!
    @logged_user_id = user.id
    Tools::PersonalMCPRequestHandler.new(user)
  end

  def oauth_handler(key)
    grant = MCPAuthToken.authenticate(key)
    return nil if grant.nil?

    grant.note_use!
    @logged_user_id = grant.user_id
    Tools::PersonalMCPRequestHandler.new(grant.user, credential: Tools::PersonalMCP::Credential.grant(grant))
  end

  def presented_key
    request.headers[MCP::SessionKey::HEADER].presence || bearer_token.presence
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    header.delete_prefix("Bearer ") if header.start_with?("Bearer ")
  end

  def unauthorized_response
    challenge = oauth_challenge
    response.set_header("WWW-Authenticate", challenge) if challenge
    render json: {
      jsonrpc: "2.0",
      id: nil,
      error: { code: -32000, message: "Unauthorized: valid session key required" }
    }, status: :unauthorized
  end

  # Where a client that can sign in finds out how (RFC 9728 §5.1) — without this
  # header Claude never learns there is an authorization server. Not for an
  # agent container's session key: nothing there can sign in, and an agent CLI
  # that sees the challenge would wait on a browser no one opens.
  def oauth_challenge
    key = presented_key
    return nil if request.headers[MCP::SessionKey::HEADER].present?
    return nil if key.present? && !key.start_with?(User::MCP_TOKEN_PREFIX) && !MCPAuthToken.access_token?(key)

    resource = MCPAuth::Endpoints.resource_for_path(request.path)
    return nil if resource.nil?

    error = ' error="invalid_token",' if key.present?
    "Bearer#{error} resource_metadata=\"#{MCPAuth::Endpoints.resource_metadata_url(resource)}\", " \
      "scope=\"#{MCPAuth::Endpoints::SCOPE}\""
  end
end
