class CreateWorkflowRunAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :workflow_run_assets do |t|
      t.references :workflow_run, null: false, foreign_key: true
      t.references :produced_by_step_run, null: true, foreign_key: { to_table: :step_runs }
      t.string :name, null: false
      t.string :s3_key
      t.string :content_type
      t.integer :file_size

      t.timestamps
    end
  end
end
