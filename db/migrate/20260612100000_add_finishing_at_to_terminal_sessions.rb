# frozen_string_literal: true

class AddFinishingAtToTerminalSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :terminal_sessions, :finishing_at, :datetime
  end
end
