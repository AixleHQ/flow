# frozen_string_literal: true

module Oauth
  # Session-start preflight (oauth-unification §4.6). Given the MCP servers a session
  # will use and the acting user, returns the OAuth servers that still need an
  # interactive connection — so the launch can be blocked with a "Connect …" CTA
  # rather than silently failing at provisioning when TokenService raises.
  module Preflight
    module_function

    # @param servers [Enumerable<MCPServer>]
    # @param user [User] the acting user (identity for per_user servers)
    # @return [Array<Hash>] one entry per server needing connection:
    #   { mcp_server_id:, name:, connect_url: }. Empty when everything is usable.
    def missing_connections(servers, user:)
      servers.filter_map do |server|
        next unless oauth_server?(server)
        next if usable?(server, user)

        {
          mcp_server_id: server.id,
          name: server.name,
          connect_url: "/oauth/mcp/#{server.id}/connect"
        }
      end
    end

    def oauth_server?(server)
      server.respond_to?(:auth_type_oauth?) && server.auth_type_oauth?
    end

    # A server is usable when the acting identity has a non-revoked, non-errored
    # credential that either has a still-valid access token or can be refreshed.
    # No network here — the actual refresh still happens at provisioning; this only
    # catches the common never-connected / errored / dead-and-unrefreshable cases.
    def usable?(server, user)
      owner = server.credential_scope_per_user? ? user : server.scope
      return false if owner.nil?

      cred = OauthCredential.for_mcp_server(server).for_owner(owner)
                            .where.not(status: :revoked).order(updated_at: :desc).first
      return false if cred.nil? || cred.error?

      cred.access_token.present? && (!cred.expired? || cred.refreshable?)
    end
  end
end
