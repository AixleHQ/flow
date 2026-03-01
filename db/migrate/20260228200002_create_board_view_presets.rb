# frozen_string_literal: true

class CreateBoardViewPresets < ActiveRecord::Migration[8.0]
  def change
    create_table :board_view_presets do |t|
      t.references :board, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.jsonb :filters, null: false, default: {}
      t.boolean :shared, null: false, default: false
      t.timestamps
    end

    add_index :board_view_presets, [ :board_id, :user_id, :name ], unique: true
    add_index :board_view_presets, [ :board_id, :shared ]
  end
end
