# frozen_string_literal: true

class CreateToolResults < ActiveRecord::Migration[8.1]
  def change
    create_table :tool_results do |t|
      t.string :execution_id, null: false
      t.string :state, null: false, default: "processing"
      t.references :tool, null: false, foreign_key: true
      t.references :terminal_session, foreign_key: true
      t.references :step_run, foreign_key: true
      t.integer :exit_code
      t.string :error
      t.integer :duration_ms
      t.text :stdout_data
      t.text :stderr_data
      t.text :result_data_data
      t.text :output_data
      t.timestamps

      t.index :execution_id, unique: true
    end
  end
end
