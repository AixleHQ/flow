# frozen_string_literal: true

class CreateLlmCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_calls do |t|
      t.references :workflow_run, null: true, foreign_key: true, index: false
      t.references :step_run,     null: true, foreign_key: true, index: false
      t.references :terminal_session, null: false, foreign_key: true, index: false

      t.string  :model,              null: false
      t.integer :input_tokens,       null: false, default: 0
      t.integer :output_tokens,      null: false, default: 0
      t.integer :cache_read_tokens,  null: false, default: 0
      t.integer :cache_write_tokens, null: false, default: 0
      t.decimal :total_cents_precise, precision: 12, scale: 8, null: false, default: "0.0"
      t.string  :source,             null: false
      t.datetime :occurred_at,       null: false

      t.timestamps
    end

    add_index :llm_calls, %i[workflow_run_id occurred_at]
    add_index :llm_calls, %i[workflow_run_id step_run_id]
    add_index :llm_calls, %i[terminal_session_id occurred_at]
  end
end
