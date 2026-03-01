# frozen_string_literal: true

class CreateBoards < ActiveRecord::Migration[8.0]
  def change
    create_table :boards do |t|
      t.references :project, null: false, foreign_key: true, index: { unique: true }
      t.string :name, null: false
      t.string :preset_origin

      t.timestamps
    end
  end
end
