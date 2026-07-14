# frozen_string_literal: true

class AddDeletedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :deleted_at, :datetime
    add_index :users, :deleted_at, where: "deleted_at IS NOT NULL"
  end
end
