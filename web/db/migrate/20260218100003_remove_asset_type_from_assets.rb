# frozen_string_literal: true

class RemoveAssetTypeFromAssets < ActiveRecord::Migration[8.1]
  def change
    remove_column :assets, :asset_type, :string, null: false, default: "document"
  end
end
