# frozen_string_literal: true

# The actionmcp + solid_mcp gems are replaced by the official mcp gem serving
# a stateless per-request server (no server-side MCP session state), so their
# tables go away. Irreversible: the data is gem-internal session/message
# plumbing with a 7-day TTL, not business state.
class DropActionMCPTables < ActiveRecord::Migration[8.1]
  def up
    %i[
      action_mcp_session_messages
      action_mcp_session_resources
      action_mcp_session_subscriptions
      action_mcp_session_tasks
      action_mcp_sse_events
      action_mcp_sessions
      solid_mcp_messages
    ].each { |table| drop_table table, if_exists: true }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
