# frozen_string_literal: true

class ReplaceProvenanceWithSourceOnAssetVersions < ActiveRecord::Migration[8.1]
  def change
    remove_column :asset_versions, :provenance, :jsonb, null: false, default: {}
    add_column :asset_versions, :source, :string, null: false, default: "upload"
  end
end
