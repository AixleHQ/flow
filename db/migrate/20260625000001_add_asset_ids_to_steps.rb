# frozen_string_literal: true

class AddAssetIdsToSteps < ActiveRecord::Migration[8.0]
  def change
    add_column :steps, :asset_ids, :jsonb, default: [], null: false
  end
end
