class AddContextMetadataToTerminalSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :terminal_sessions, :context_metadata, :jsonb
  end
end
