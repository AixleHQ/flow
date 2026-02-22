# frozen_string_literal: true

class CreateSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :steps do |t|
      t.references :workflow, null: false, foreign_key: true
      t.references :agent, null: true, foreign_key: true
      t.integer :position, null: false
      t.string :name, null: false
      t.text :description
      t.text :instructions
      t.boolean :allow_non_interactive, null: false, default: false
      t.string :skip_policy, null: false, default: "never"
      t.jsonb :input_asset_specs, null: false, default: []
      t.jsonb :output_asset_specs, null: false, default: []
      t.string :agent_runtime
      t.jsonb :tool_ids, null: false, default: []
      t.string :on_failure, null: false, default: "fail"
      t.integer :max_retries, null: false, default: 0

      t.timestamps
    end

    add_index :steps, %i[workflow_id position], unique: true
  end
end
