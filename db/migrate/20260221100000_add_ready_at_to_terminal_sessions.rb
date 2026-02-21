# frozen_string_literal: true

class AddReadyAtToTerminalSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :terminal_sessions, :ready_at, :datetime

    # Migrate existing data: sessions that were "running" had an implicit ready state
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE terminal_sessions
          SET ready_at = started_at
          WHERE state IN ('running', 'stopped', 'collected')
            AND started_at IS NOT NULL
        SQL

        # Migrate old states to new ones
        execute "UPDATE terminal_sessions SET state = 'ready' WHERE state = 'running'"
        execute "UPDATE terminal_sessions SET state = 'finished' WHERE state IN ('stopped', 'collected', 'cancelled')"
      end
    end
  end
end
