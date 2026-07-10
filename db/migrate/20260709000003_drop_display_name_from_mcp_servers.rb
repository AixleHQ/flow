# frozen_string_literal: true

# Drop mcp_servers.display_name. The server now has a single human `name`; the
# lowercase protocol identifier used in agent MCP config (.mcp.json keys and the
# `mcp__<key>__tool` namespace) is derived from `name` at config-generation time
# (MCPServer.config_key_for), so a stored slug column is no longer needed.
class DropDisplayNameFromMCPServers < ActiveRecord::Migration[8.1]
  def change
    remove_column :mcp_servers, :display_name, :string, null: false
  end
end
