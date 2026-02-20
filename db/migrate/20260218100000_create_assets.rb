# frozen_string_literal: true

class CreateAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :assets do |t|
      t.string :name, null: false
      t.string :asset_type, null: false, default: "document"
      t.string :folder
      t.string :tags, array: true, default: []
      t.boolean :public, default: false
      t.string :public_token
      t.string :scope_type, null: false
      t.bigint :scope_id, null: false
      t.bigint :created_by_id, null: false
      t.bigint :step_run_id
      t.timestamps
    end

    add_index :assets, %i[scope_type scope_id name], unique: true
    add_index :assets, %i[scope_type scope_id]
    add_index :assets, :created_by_id
    add_index :assets, :step_run_id, where: "step_run_id IS NOT NULL"
    add_foreign_key :assets, :users, column: :created_by_id
  end
end
