# frozen_string_literal: true

# POST /mcp-oauth/revoke (RFC 7009). Revoking either token of a grant ends the
# whole grant: an app that hands back a token is disconnecting. Answers 200 for
# a token it does not know, as the RFC requires.
class MCPAuth::RevocationsController < ActionController::API
  include MCPAuth::ClientAuthentication

  def create
    token = MCPAuthToken.find_by_plaintext(params[:token], kind: "refresh") ||
            MCPAuthToken.find_by_plaintext(params[:token], kind: "access")
    client_id = presented_client_id
    token.grant.revoke! if token && (client_id.blank? || client_id == token.grant.client_id)
    head :ok
  end
end
