class CreateStepRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :step_runs do |t|
      t.references :workflow_run, null: false, foreign_key: true
      t.references :step, null: false, foreign_key: true
      t.references :terminal_session, null: true, foreign_key: true
      t.string :state, null: false, default: "pending"
      t.text :step_note
      t.string :skip_reason
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message

      t.timestamps
    end

    add_index :step_runs, [:workflow_run_id, :state]
  end
end
