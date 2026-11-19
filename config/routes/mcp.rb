# frozen_string_literal: true

# Aixle MCP server endpoint (Model Context Protocol for agent containers).
# /action_mcp is the legacy path agent containers are configured with
# (Settings.mcp.server_url); /mcp is the forward-looking alias.
match "/action_mcp", to: "mcp#handle", via: %i[get post delete]
match "/mcp", to: "mcp#handle", via: %i[get post delete]

# Aixle as the OAuth authorization server of the personal MCP server
# (docs/design/mcp-oauth-server.md). The authorize screen needs the browser
# session, so it is drawn with the web routes.
get "/.well-known/oauth-protected-resource(/*resource_path)", to: "mcp_auth/metadata#protected_resource",
                                                              format: false
get "/.well-known/oauth-authorization-server", to: "mcp_auth/metadata#authorization_server", format: false
post "/mcp-oauth/token", to: "mcp_auth/tokens#create", as: :mcp_oauth_token
post "/mcp-oauth/register", to: "mcp_auth/registrations#create", as: :mcp_oauth_register
post "/mcp-oauth/revoke", to: "mcp_auth/revocations#create", as: :mcp_oauth_revoke
