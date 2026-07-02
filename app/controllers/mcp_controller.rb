# frozen_string_literal: true

# The Aixle MCP server endpoint for agent containers. Authenticates the
# TerminalSession from its per-session mcp_key (X-Session-Key header,
# Authorization bearer, or session_key param — same contract as the old
# actionmcp gateway), then serves the request from a stateless per-request
# MCP::Server (Tools::MCPRequestHandler).
class MCPController < ActionController::API
  def handle
    session = authenticate_terminal_session
    return unauthorized_response if session.nil?

    status, headers, body = Tools::MCPRequestHandler.new(session).call(request)
    headers.each { |k, v| response.set_header(k, v) }
    render plain: Array(body).join, status: status
  end

  private

  def authenticate_terminal_session
    key = request.headers["X-Session-Key"].presence ||
          bearer_token.presence ||
          params[:session_key].presence
    return nil if key.blank?

    session = TerminalSession.find_by(mcp_key: key)
    session if session&.active?
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
