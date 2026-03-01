# frozen_string_literal: true

class CreateColumnWorkflowBindings < ActiveRecord::Migration[8.0]
  def change
    create_table :column_workflow_bindings do |t|
      t.references :board_column, null: false, foreign_key: true, index: { unique: true }
      t.references :workflow, null: false, foreign_key: true
      t.string :trigger_mode, null: false, default: "manual"
      t.integer :cooldown_seconds, null: false, default: 5
      t.timestamps
    end
  end
end
