# frozen_string_literal: true

class CreateIntegrations < ActiveRecord::Migration[8.0]
  def change
    create_table :integrations do |t|
      t.string :name, null: false
      t.string :provider, null: false
      t.text :credentials
      t.jsonb :settings, default: {}
      t.string :status, null: false, default: "inactive"
      t.bigint :company_id, null: false
      t.bigint :connected_by_id, null: false

      t.timestamps
    end

    add_index :integrations, %i[company_id provider]
    add_index :integrations, :company_id
    add_index :integrations, :status
    add_foreign_key :integrations, :companies
    add_foreign_key :integrations, :users, column: :connected_by_id
  end
end
