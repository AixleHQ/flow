class AddStepOverridesToWorkflowRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :workflow_runs, :step_overrides, :jsonb, default: {}, null: false
  end
end
