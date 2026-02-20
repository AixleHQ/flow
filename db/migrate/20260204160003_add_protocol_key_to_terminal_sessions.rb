# frozen_string_literal: true

class AddProtocolKeyToTerminalSessions < ActiveRecord::Migration[8.0]
  def change
    # MCP authentication key for terminal sessions
    add_column :terminal_sessions, :mcp_key, :string
    add_index :terminal_sessions, :mcp_key, unique: true
  end
end
