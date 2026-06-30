# frozen_string_literal: true

class CreateIntegrationData < ActiveRecord::Migration[8.1]
  def change
    create_table :integration_data do |t|
      t.references :integration, null: false, foreign_key: { on_delete: :cascade }
      t.string     :key,         null: false
      t.jsonb      :value,       null: false, default: {}
      t.datetime   :expires_at,  null: true
      t.timestamps
    end

    add_index :integration_data, %i[integration_id key],
              unique: true,
              name:   "ix_integration_data_integration_key"

    add_index :integration_data, :expires_at,
              where: "expires_at IS NOT NULL",
              name:  "ix_integration_data_expires_at"
  end
end
