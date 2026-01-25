# frozen_string_literal: true

class AddWebsocketTokenToTerminalSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :terminal_sessions, :websocket_token, :string
    add_index :terminal_sessions, :websocket_token, unique: true
  end
end
