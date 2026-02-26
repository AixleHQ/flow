class AddDependsOnStepIdsToSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :steps, :depends_on_step_ids, :jsonb, default: [], null: false
  end
end
