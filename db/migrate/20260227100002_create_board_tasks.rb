# frozen_string_literal: true

class CreateBoardTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :board_tasks do |t|
      t.references :board, null: false, foreign_key: true
      t.references :board_column, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :task_type, null: false, default: "not_specified"
      t.string :priority
      t.references :assignee, foreign_key: { to_table: :users }, null: true
      t.integer :position, null: false
      t.references :parent_task, foreign_key: { to_table: :board_tasks }, null: true
      t.string :tags, array: true, default: []

      t.timestamps
    end
  end
end
