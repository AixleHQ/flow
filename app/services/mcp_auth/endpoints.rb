# frozen_string_literal: true

module MCPAuth
  # Where Aixle's authorization server for the personal MCP lives, and the two
  # discovery documents that tell a client so: protected resource metadata
  # (RFC 9728) for each MCP URL, authorization server metadata (RFC 8414).
  module Endpoints
    SCOPE = "mcp"

    module_function

    def issuer = "#{Settings.protocol}://#{Settings.domain}"
    def authorization_endpoint = "#{issuer}/mcp-oauth/authorize"
    def token_endpoint = "#{issuer}/mcp-oauth/token"
    def registration_endpoint = "#{issuer}/mcp-oauth/register"
    def revocation_endpoint = "#{issuer}/mcp-oauth/revoke"

    # The MCP URLs a token is for. A client must be told the URL it was given,
    # byte for byte (Claude compares `resource` with what the person typed), so
    # /mcp is Tools::PersonalMCP.public_url and /action_mcp is the alias beside it.
    def resources
      public_url = Tools::PersonalMCP.public_url
      [ public_url, "#{origin(public_url)}/action_mcp" ].uniq
    end

    # nil when `path` is no MCP endpoint of ours. A bare
    # /.well-known/oauth-protected-resource stands for the public URL.
    def resource_for_path(path)
      path = "/#{path.to_s.delete_prefix('/')}".delete_suffix("/")
      return resources.first if path.empty?

      resources.find { |resource| URI(resource).path == path }
    end

    def resource?(value)
      value.present? && resources.include?(value.to_s.delete_suffix("/"))
    end

    def resource_metadata_url(resource)
      "#{origin(resource)}/.well-known/oauth-protected-resource#{URI(resource).path}"
    end

    def protected_resource_metadata(resource)
      {
        resource: resource,
        authorization_servers: [ issuer ],
        scopes_supported: [ SCOPE ],
        bearer_methods_supported: [ "header" ],
        resource_name: "Aixle Flow"
      }
    end

    # `token_endpoint_auth_methods_supported: ["none"]` and
    # `client_id_metadata_document_supported` together are what makes Claude use
    # CIMD instead of registering a new client on every connection.
    def authorization_server_metadata
      {
        issuer: issuer,
        authorization_endpoint: authorization_endpoint,
        token_endpoint: token_endpoint,
        registration_endpoint: registration_endpoint,
        revocation_endpoint: revocation_endpoint,
        scopes_supported: [ SCOPE ],
        response_types_supported: [ "code" ],
        response_modes_supported: [ "query" ],
        grant_types_supported: %w[authorization_code refresh_token],
        token_endpoint_auth_methods_supported: [ "none" ],
        revocation_endpoint_auth_methods_supported: [ "none" ],
        code_challenge_methods_supported: [ "S256" ],
        client_id_metadata_document_supported: true,
        authorization_response_iss_parameter_supported: true
      }
    end

    def origin(url)
      uri = URI(url)
      default_port = uri.scheme == "https" ? 443 : 80
      uri.port == default_port ? "#{uri.scheme}://#{uri.host}" : "#{uri.scheme}://#{uri.host}:#{uri.port}"
    end
  end
end
