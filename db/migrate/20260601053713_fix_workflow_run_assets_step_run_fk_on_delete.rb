class FixWorkflowRunAssetsStepRunFkOnDelete < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :workflow_run_assets, column: :produced_by_step_run_id
    add_foreign_key :workflow_run_assets, :step_runs,
                    column: :produced_by_step_run_id,
                    on_delete: :nullify
  end

  def down
    remove_foreign_key :workflow_run_assets, column: :produced_by_step_run_id
    add_foreign_key :workflow_run_assets, :step_runs,
                    column: :produced_by_step_run_id
  end
end
