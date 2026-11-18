# frozen_string_literal: true

# POST /mcp-oauth/register — Dynamic Client Registration (RFC 7591) for MCP
# clients that do not identify themselves with a metadata document URL. Every
# registration is a public client: whatever auth method it asks for, it is told
# `none`, and PKCE does what a secret would.
class MCPAuth::RegistrationsController < ActionController::API
  GRANT_TYPES = %w[authorization_code refresh_token].freeze

  def create
    redirect_uris = params[:redirect_uris]
    unless redirect_uris.is_a?(Array) && redirect_uris.all?(String)
      return registration_error("invalid_redirect_uri", "redirect_uris must be a list of URIs")
    end
    if params[:grant_types].present? && (Array(params[:grant_types]) - GRANT_TYPES).any?
      return registration_error("invalid_client_metadata", "Only #{GRANT_TYPES.join(' and ')} are supported")
    end

    client = MCPAuthClient.register!(client_name: params[:client_name], redirect_uris: redirect_uris)
    render status: :created, json: {
      client_id: client.client_id,
      client_id_issued_at: client.created_at.to_i,
      client_name: client.client_name,
      redirect_uris: client.redirect_uris,
      grant_types: GRANT_TYPES,
      response_types: [ "code" ],
      token_endpoint_auth_method: "none"
    }.compact
  rescue ActiveRecord::RecordInvalid => e
    registration_error("invalid_redirect_uri", e.record.errors.full_messages.to_sentence)
  end

  private

  def registration_error(code, description)
    render json: { error: code, error_description: description }, status: :bad_request
  end
end
