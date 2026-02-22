class CreateWorkflowRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :workflow_runs do |t|
      t.references :workflow, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :state, null: false, default: "pending"
      t.string :mode, null: false, default: "interactive"
      t.jsonb :input_asset_ids, default: []
      t.jsonb :shared_context, default: {}
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :workflow_runs, :state
    add_index :workflow_runs, [:workflow_id, :state]
  end
end
