# frozen_string_literal: true

class CreateWorkflows < ActiveRecord::Migration[8.1]
  def change
    create_table :workflows do |t|
      t.string :name, null: false
      t.text :description
      t.jsonb :config, null: false, default: {}
      t.string :scope_type, null: false
      t.integer :scope_id, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :workflows, %i[scope_type scope_id]
    add_index :workflows, %i[scope_type scope_id name], unique: true, where: "deleted_at IS NULL", name: "index_workflows_on_scope_and_name_unique"
    add_index :workflows, :deleted_at
  end
end
