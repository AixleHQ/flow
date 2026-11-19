# frozen_string_literal: true

# POST /mcp-oauth/token (MCPAuth::TokenExchange). Clients send
# application/x-www-form-urlencoded (RFC 6749 §4.1.3); JSON is read as well.
class MCPAuth::TokensController < ActionController::API
  include MCPAuth::ClientAuthentication

  def create
    response.set_header("Cache-Control", "no-store")
    render json: MCPAuth::TokenExchange.call(token_params)
  rescue MCPAuth::TokenExchange::Error => e
    render json: { error: e.code, error_description: e.message }, status: e.status
  end

  private

  def token_params
    params.permit(:grant_type, :code, :redirect_uri, :code_verifier, :refresh_token, :client_id, :resource, :scope)
          .to_h.merge("client_id" => presented_client_id).compact
  end
end
