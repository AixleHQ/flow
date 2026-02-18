# frozen_string_literal: true

class AddDeletedAtToAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :assets, :deleted_at, :datetime
    add_index :assets, :deleted_at
  end
end
