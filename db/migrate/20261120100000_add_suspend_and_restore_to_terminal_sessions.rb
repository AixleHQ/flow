# frozen_string_literal: true

class AddSuspendAndRestoreToTerminalSessions < ActiveRecord::Migration[8.1]
  def change
    add_reference :terminal_sessions, :restored_from_session,
                  foreign_key: { to_table: :terminal_sessions, on_delete: :nullify }, index: true
    add_column :terminal_sessions, :suspended_at, :datetime
    add_column :terminal_sessions, :restore_expires_at, :datetime
    add_index :terminal_sessions, :restore_expires_at, where: "restore_expires_at IS NOT NULL"

    create_table :session_checkpoints do |t|
      t.references :terminal_session, null: false, index: { unique: true },
                                      foreign_key: { on_delete: :cascade }
      t.text :archive_data
      t.bigint :byte_size
      t.jsonb :manifest, null: false, default: {}
      t.timestamps
    end
  end
end
