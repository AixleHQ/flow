# frozen_string_literal: true

class AddDeletedAtToTools < ActiveRecord::Migration[7.2]
  def change
    add_column :tools, :deleted_at, :datetime
    add_index :tools, :deleted_at
  end
end
