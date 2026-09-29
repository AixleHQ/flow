# frozen_string_literal: true

# Which versions a run actually executed: the workflow version each step launched
# with, and the agent, skill, custom tool and MCP server versions each session got.
class RecordLaunchedVersions < ActiveRecord::Migration[8.1]
  def change
    add_reference :step_runs, :workflow_version, foreign_key: { to_table: :entity_versions, on_delete: :nullify },
                                                 index: { where: "workflow_version_id IS NOT NULL" }
    add_column :terminal_sessions, :version_ids, :jsonb, null: false, default: {}
  end
end
