# frozen_string_literal: true

class RemoveWebsocketUrlFromTerminalSessions < ActiveRecord::Migration[8.0]
  def change
    remove_column :terminal_sessions, :websocket_url, :string
  end
end
