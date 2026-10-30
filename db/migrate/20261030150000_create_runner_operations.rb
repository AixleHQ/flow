# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §2.3, the columns §15 task 5b reads and
# writes: the queue the platform puts an environment's ops on, which the runner
# gateway's long-poll delivers and the op results complete. Like
# runner_credentials, a row carries company_id directly, the §2 composite key
# (runner_id, company_id) ties it to its runner's company, and
# (runner_environment_id, runner_id) ties its environment to the same runner.
class CreateRunnerOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :runner_operations do |t|
      t.references :runner, null: false, foreign_key: { on_delete: :cascade }
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      # Indexed by the unique (runner_environment_id, sequence) index below.
      t.references :runner_environment, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.bigint :sequence, null: false
      t.string :op, null: false
      t.text :encrypted_payload
      t.string :state, null: false
      t.jsonb :result
      t.datetime :deadline_at, null: false
      t.datetime :delivered_at
      t.datetime :completed_at
      t.timestamps

      t.index %i[runner_environment_id sequence], unique: true
    end

    add_foreign_key :runner_operations, :runners, column: %i[runner_id company_id], primary_key: %i[id company_id],
                                                  on_delete: :cascade, name: "fk_runner_operations_runner_company"
    add_foreign_key :runner_operations, :runner_environments, column: %i[runner_environment_id runner_id],
                                                              primary_key: %i[id runner_id], on_delete: :cascade,
                                                              name: "fk_runner_operations_environment_runner"
  end
end
