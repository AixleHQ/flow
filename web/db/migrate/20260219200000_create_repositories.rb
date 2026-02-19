# frozen_string_literal: true

class CreateRepositories < ActiveRecord::Migration[8.0]
  def change
    create_table :repositories do |t|
      t.string :full_name, null: false
      t.string :default_branch, null: false, default: "main"
      t.string :clone_url, null: false
      t.boolean :is_private, default: false
      t.text :description
      t.datetime :last_fetched_at
      t.bigint :integration_id, null: false
      t.string :scope_type, null: false
      t.bigint :scope_id, null: false

      t.timestamps
    end

    add_index :repositories, %i[scope_type scope_id full_name], unique: true, name: "idx_repositories_scope_full_name"
    add_index :repositories, %i[scope_type scope_id]
    add_index :repositories, :integration_id
    add_foreign_key :repositories, :integrations
  end
end
