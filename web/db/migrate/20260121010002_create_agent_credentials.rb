# frozen_string_literal: true

class CreateAgentCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :agent_type, null: false # codex, cursor_cli, open_code, claude_code
      t.text :credentials_encrypted
      t.string :status, default: 'pending', null: false # pending, configured, expired
      t.datetime :configured_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :agent_credentials, [:user_id, :agent_type], unique: true
    add_index :agent_credentials, :status
  end
end
