# frozen_string_literal: true

class CreateAssetVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :asset_versions do |t|
      t.references :asset, null: false, foreign_key: true
      t.integer :version, null: false, default: 1
      t.text :file_data
      t.string :content_type
      t.bigint :file_size
      t.jsonb :provenance, default: {}
      t.bigint :uploaded_by_id, null: false
      t.timestamps
    end

    add_index :asset_versions, %i[asset_id version], unique: true
    add_foreign_key :asset_versions, :users, column: :uploaded_by_id
  end
end
