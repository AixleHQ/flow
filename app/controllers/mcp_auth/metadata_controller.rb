# frozen_string_literal: true

# The discovery documents of the personal MCP's authorization server
# (docs/design/mcp-oauth-server.md): RFC 9728 protected resource metadata per MCP
# URL, and RFC 8414 authorization server metadata. Public, and the same for
# everyone.
class MCPAuth::MetadataController < ActionController::API
  before_action { expires_in 5.minutes, public: true }

  def protected_resource
    resource = MCPAuth::Endpoints.resource_for_path(params[:resource_path])
    return head(:not_found) if resource.nil?

    render json: MCPAuth::Endpoints.protected_resource_metadata(resource)
  end

  def authorization_server
    render json: MCPAuth::Endpoints.authorization_server_metadata
  end
end
