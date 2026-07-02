# frozen_string_literal: true

# The Aixle MCP server endpoint for agent containers. Authenticates the
# TerminalSession from its per-session mcp_key (X-Session-Key header,
# Authorization bearer, or session_key param — same contract as the old
# actionmcp gateway), then serves the request from a stateless per-request
# MCP::Server (Tools::MCPRequestHandler).
class MCPController < ActionController::API
  def handle
    handler = resolve_handler
    return unauthorized_response if handler.nil?

    status, headers, body = handler.call(request)
    headers.each { |k, v| response.set_header(k, v) }
    render plain: Array(body).join, status: status
  end

  private

  # Two principals on one endpoint, split by credential shape: an
  # amcp_-prefixed personal token serves the user-level server; anything else
  # is a terminal session's mcp_key serving the session-scoped server.
  def resolve_handler
    key = request.headers["X-Session-Key"].presence ||
          bearer_token.presence ||
          params[:session_key].presence
    return nil if key.blank?

    if key.start_with?(User::MCP_TOKEN_PREFIX)
      user = User.find_by_mcp_token(key)
      return nil if user.nil?

      user.update_columns(mcp_token_last_used_at: Time.current)
      Tools::PersonalMCPRequestHandler.new(user)
    else
      session = TerminalSession.find_by(mcp_key: key)
      return nil unless session&.active?

      Tools::MCPRequestHandler.new(session)
    end
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    header.delete_prefix("Bearer ") if header.start_with?("Bearer ")
  end

  def unauthorized_response
    render json: {
      jsonrpc: "2.0",
      id: nil,
      error: { code: -32000, message: "Unauthorized: valid session key required" }
    }, status: :unauthorized
  end
end
