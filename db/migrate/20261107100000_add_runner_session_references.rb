# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §2.2, §2.3, §2.4, the columns §15 task 8a
# reads and writes:
#
# - terminal_sessions.runner_environment_id: the machine a runner session ran
#   on. The key (runner_environment_id, runner_id) → runner_environments (id,
#   runner_id) ties it to the session's own runner, whose company is already
#   tied to the session's by fk_terminal_sessions_runner_company.
# - runner_environments.current_session_id: the session that holds the machine
#   now. At most one per machine, and a machine without one is free.
# - runner_operations.terminal_session_id: the session a session op is for,
#   delivered as the op envelope's `session_id`. Environment ops have none.
class AddRunnerSessionReferences < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :terminal_sessions, :runner_environment_id, :bigint, if_not_exists: true
    add_index :terminal_sessions, :runner_environment_id, algorithm: :concurrently, if_not_exists: true
    add_foreign_key :terminal_sessions, :runner_environments, on_delete: :nullify, validate: false, if_not_exists: true
    validate_foreign_key :terminal_sessions, :runner_environments
    unless foreign_key_exists?(:terminal_sessions, name: "fk_terminal_sessions_environment_runner")
      add_foreign_key :terminal_sessions, :runner_environments, column: %i[runner_environment_id runner_id],
                                                                primary_key: %i[id runner_id], validate: false,
                                                                name: "fk_terminal_sessions_environment_runner"
      validate_foreign_key :terminal_sessions, name: "fk_terminal_sessions_environment_runner"
    end

    add_column :runner_environments, :current_session_id, :bigint, if_not_exists: true
    add_index :runner_environments, :current_session_id, unique: true, algorithm: :concurrently, if_not_exists: true
    add_foreign_key :runner_environments, :terminal_sessions, column: :current_session_id, on_delete: :nullify,
                                                              validate: false, if_not_exists: true
    validate_foreign_key :runner_environments, :terminal_sessions, column: :current_session_id

    add_column :runner_operations, :terminal_session_id, :bigint, if_not_exists: true
    add_index :runner_operations, :terminal_session_id, algorithm: :concurrently, if_not_exists: true
    add_foreign_key :runner_operations, :terminal_sessions, on_delete: :cascade, validate: false, if_not_exists: true
    validate_foreign_key :runner_operations, :terminal_sessions
    # The 7-day prune selects by state and age.
    add_index :runner_operations, %i[state completed_at], algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :runner_operations, %i[state completed_at], if_exists: true
    remove_foreign_key :runner_operations, :terminal_sessions, if_exists: true
    remove_column :runner_operations, :terminal_session_id, if_exists: true
    remove_foreign_key :runner_environments, :terminal_sessions, column: :current_session_id, if_exists: true
    remove_column :runner_environments, :current_session_id, if_exists: true
    remove_foreign_key :terminal_sessions, name: "fk_terminal_sessions_environment_runner", if_exists: true
    remove_foreign_key :terminal_sessions, :runner_environments, if_exists: true
    remove_column :terminal_sessions, :runner_environment_id, if_exists: true
  end
end
