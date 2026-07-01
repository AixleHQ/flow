# frozen_string_literal: true

class AddUserCreatedIndexToTerminalSessions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :terminal_sessions, %i[user_id created_at],
              name: "index_terminal_sessions_on_user_id_and_created_at",
              algorithm: :concurrently,
              if_not_exists: true
    add_index :workflow_runs, %i[user_id created_at],
              name: "index_workflow_runs_on_user_id_and_created_at",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
