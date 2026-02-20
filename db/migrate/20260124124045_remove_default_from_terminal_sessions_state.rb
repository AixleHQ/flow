class RemoveDefaultFromTerminalSessionsState < ActiveRecord::Migration[8.0]
  def change
    change_column_default :terminal_sessions, :state, from: 'not_started', to: nil
  end
end
