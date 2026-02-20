# frozen_string_literal: true

class AddSessionConfigToTerminalSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :terminal_sessions, :session_config, :jsonb, default: {}, null: false
  end
end
