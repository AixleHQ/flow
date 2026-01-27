class CreateTerminalSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :terminal_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project, null: true, foreign_key: true  # Nullable for auth_setup sessions
      t.string :session_type, null: false
      t.string :agent_type  # Required for auth_setup, optional for others
      t.string :state, null: false, default: 'not_started'
      t.string :temporal_workflow_id
      t.string :temporal_run_id
      t.string :container_id
      t.string :websocket_url
      t.string :artifacts_path
      t.text :error_message
      t.jsonb :metadata, default: {}
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :collected_at

      t.timestamps
    end

    add_index :terminal_sessions, :session_type
    add_index :terminal_sessions, :state
    add_index :terminal_sessions, :temporal_workflow_id
    add_index :terminal_sessions, [:user_id, :state]
    add_index :terminal_sessions, [:user_id, :session_type]
  end
end
