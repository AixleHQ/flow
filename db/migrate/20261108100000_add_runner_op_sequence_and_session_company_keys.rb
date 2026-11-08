# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §2.3, §2.4, task 8a, Fix CR round 4:
#
# - runner_environments.op_sequence: the last sequence an op of the environment
#   took. Runners::Operations.enqueue! takes the next one under the row lock it
#   already holds, so the prune, and a session's deletion with its ops, can
#   remove any finished op without the sequence going back.
# - The company keys of the session references (docs/project/context.md,
#   "Database keys"): runner_operations (terminal_session_id, company_id) and
#   runner_environments (current_session_id, company_id) →
#   terminal_sessions (id, company_id), so a row never names another company's
#   session. The single-column keys stay for their delete actions: a deleted
#   session's ops go with it, and the machine it held stops holding it. The
#   machine's key is deferred to the commit: its `SET NULL` comes from the
#   single-column key, which a check at the end of the delete statement could
#   run before.
class AddRunnerOpSequenceAndSessionCompanyKeys < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :runner_environments, :op_sequence, :bigint, null: false, default: 0, if_not_exists: true
    execute <<~SQL.squish
      UPDATE runner_environments SET op_sequence = newest.sequence
      FROM (SELECT runner_environment_id, MAX(sequence) AS sequence FROM runner_operations GROUP BY runner_environment_id) newest
      WHERE newest.runner_environment_id = runner_environments.id AND runner_environments.op_sequence < newest.sequence
    SQL

    add_index :terminal_sessions, %i[id company_id], unique: true, algorithm: :concurrently, if_not_exists: true

    unless foreign_key_exists?(:runner_operations, name: "fk_runner_operations_session_company")
      add_foreign_key :runner_operations, :terminal_sessions, column: %i[terminal_session_id company_id],
                                                              primary_key: %i[id company_id], on_delete: :cascade,
                                                              validate: false, name: "fk_runner_operations_session_company"
      validate_foreign_key :runner_operations, name: "fk_runner_operations_session_company"
    end

    unless foreign_key_exists?(:runner_environments, name: "fk_runner_environments_current_session_company")
      add_foreign_key :runner_environments, :terminal_sessions, column: %i[current_session_id company_id],
                                                                primary_key: %i[id company_id], deferrable: :deferred,
                                                                validate: false,
                                                                name: "fk_runner_environments_current_session_company"
      validate_foreign_key :runner_environments, name: "fk_runner_environments_current_session_company"
    end
  end

  def down
    remove_foreign_key :runner_environments, name: "fk_runner_environments_current_session_company", if_exists: true
    remove_foreign_key :runner_operations, name: "fk_runner_operations_session_company", if_exists: true
    remove_index :terminal_sessions, %i[id company_id], if_exists: true
    remove_column :runner_environments, :op_sequence, if_exists: true
  end
end
