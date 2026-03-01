# frozen_string_literal: true

class CreateTaskComments < ActiveRecord::Migration[8.0]
  def change
    create_table :task_comments do |t|
      t.references :board_task, null: false, foreign_key: true
      t.text :body, null: false
      t.references :author, foreign_key: { to_table: :users }, null: false
      t.string :author_type, null: false, default: "human"
      t.string :tags, array: true, default: []

      t.datetime :created_at, null: false
    end
  end
end
