# frozen_string_literal: true

class CreateTaskAssets < ActiveRecord::Migration[8.0]
  def change
    create_table :task_assets do |t|
      t.references :board_task, null: false, foreign_key: true
      t.string :name, null: false
      t.references :author, foreign_key: { to_table: :users }, null: false
      t.string :author_type, null: false, default: "human"
      t.string :tags, array: true, default: []
      t.text :file_data

      t.timestamps
    end
  end
end
