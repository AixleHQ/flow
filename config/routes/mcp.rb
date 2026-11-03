# frozen_string_literal: true

# Aixle MCP server endpoint (Model Context Protocol for agent containers).
# /action_mcp is the legacy path agent containers are configured with
# (Settings.mcp.server_url); /mcp is the forward-looking alias.
match "/action_mcp", to: "mcp#handle", via: %i[get post delete]
match "/mcp", to: "mcp#handle", via: %i[get post delete]
