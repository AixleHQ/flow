# frozen_string_literal: true

class CleanupUsageStatistics < ActiveRecord::Migration[8.1]
  def change
    remove_column :usage_statistics, :model, :string
    remove_column :usage_statistics, :cursor_token_fee_cents, :decimal, precision: 12, scale: 6, default: "0.0"
    add_column :usage_statistics, :models, :string, array: true, default: [], null: false
  end
end
