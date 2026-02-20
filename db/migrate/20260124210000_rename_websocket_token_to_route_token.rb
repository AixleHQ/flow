# frozen_string_literal: true

class RenameWebsocketTokenToRouteToken < ActiveRecord::Migration[8.0]
  def change
    rename_column :terminal_sessions, :websocket_token, :route_token
  end
end
