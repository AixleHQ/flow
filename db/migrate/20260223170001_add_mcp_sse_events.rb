# frozen_string_literal: true

class AddMCPSseEvents < ActiveRecord::Migration[8.0]
  def change
    return if table_exists?(:action_mcp_sse_events)

    create_table :action_mcp_sse_events do |t|
      t.references :session, null: false, foreign_key: { to_table: :action_mcp_sessions }, index: true, type: :string
      t.integer :event_id, null: false
      t.text :data, null: false
      t.timestamps

      t.index %i[session_id event_id], unique: true
      t.index :created_at
    end
  end
end
