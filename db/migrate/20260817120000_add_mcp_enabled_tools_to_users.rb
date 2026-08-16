# frozen_string_literal: true

# Which tools a user's personal MCP server exposes.
#
# NULL means "every tool this server has", including tools added in a later
# release — that is the only value that keeps working as the registry grows,
# so it stays the default rather than a materialized list of today's names.
# An array narrows the server to exactly those tool names.
class AddMCPEnabledToolsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :mcp_enabled_tools, :jsonb
  end
end
