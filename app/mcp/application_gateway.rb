# frozen_string_literal: true

# Custom identifier for terminal session authentication
class TerminalSessionIdentifier < ActionMCP::GatewayIdentifier
  identifier :terminal_session
  authenticates :session_key

  def resolve
    key = extract_session_key
    raise Unauthorized, "Missing session key" unless key

    session = TerminalSession.find_by(mcp_key: key)
    raise Unauthorized, "Invalid session key" unless session
    raise Unauthorized, "Session not active" unless session.active?

    session
  end

  private

  def extract_session_key
    # Try multiple header formats
    @request.env["HTTP_X_SESSION_KEY"] ||
      @request.env["HTTP_AUTHORIZATION"]&.delete_prefix("Bearer ") ||
      @request.params[:session_key]
  end
end

# Application Gateway for MCP authentication
# Authenticates requests using session mcp_key from headers
class ApplicationGateway < ActionMCP::Gateway
  # Register our custom session identifier
  identified_by TerminalSessionIdentifier
end
