# frozen_string_literal: true

# An ended session's MCP key opens nothing (MCPController refuses inactive
# sessions), but it sat in plaintext next to the live ones. Live sessions keep
# theirs: their containers hold it.
class ClearMCPKeysOfEndedSessions < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE terminal_sessions SET mcp_key = NULL
      WHERE mcp_key IS NOT NULL AND state NOT IN ('not_started', 'queued', 'running', 'ready')
    SQL
  end

  def down; end
end
