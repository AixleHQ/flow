# frozen_string_literal: true

class CreateBoardColumns < ActiveRecord::Migration[8.0]
  def change
    create_table :board_columns do |t|
      t.references :board, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false
      t.text :purpose

      t.timestamps
    end

    add_index :board_columns, %i[board_id position], unique: true
  end
end
