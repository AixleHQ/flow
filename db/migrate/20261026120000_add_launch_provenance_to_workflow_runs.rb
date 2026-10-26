# frozen_string_literal: true

class AddLaunchProvenanceToWorkflowRuns < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :workflow_runs, :source, :string, if_not_exists: true
    add_column :workflow_runs, :retried_from_run_id, :bigint, if_not_exists: true
    add_column :workflow_runs, :idempotency_key, :string, if_not_exists: true

    add_index :workflow_runs, :retried_from_run_id,
              algorithm: :concurrently, if_not_exists: true
    add_index :workflow_runs, %i[user_id idempotency_key],
              name: "index_workflow_runs_on_user_id_and_idempotency_key",
              unique: true, where: "(idempotency_key IS NOT NULL)",
              algorithm: :concurrently, if_not_exists: true

    add_foreign_key :workflow_runs, :workflow_runs, column: :retried_from_run_id,
                    on_delete: :nullify, if_not_exists: true
  end
end
