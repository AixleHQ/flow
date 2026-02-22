class CreateSubStepRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sub_step_runs do |t|
      t.references :step_run, null: false, foreign_key: true
      t.references :sub_step, null: false, foreign_key: true
      t.string :state
      t.text :note
      t.jsonb :data
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
