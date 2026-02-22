# frozen_string_literal: true

class CreateSubSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :sub_steps do |t|
      t.references :step, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :name, null: false
      t.text :description
      t.text :instructions
      t.boolean :required, null: false, default: true

      t.timestamps
    end

    add_index :sub_steps, %i[step_id position], unique: true
  end
end
