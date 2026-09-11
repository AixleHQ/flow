# frozen_string_literal: true

class CreateFolders < ActiveRecord::Migration[8.1]
  def change
    create_table :folders do |t|
      t.string :path, null: false
      t.string :scope_type, null: false
      t.bigint :scope_id, null: false
      t.bigint :created_by_id, null: false
      t.timestamps
    end

    add_index :folders, %i[scope_type scope_id path], unique: true, name: "index_folders_on_scope_and_path"
    add_index :folders, %i[scope_type scope_id]
    add_index :folders, :created_by_id
    add_foreign_key :folders, :users, column: :created_by_id
  end
end
