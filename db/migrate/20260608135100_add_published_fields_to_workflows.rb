# frozen_string_literal: true

class AddPublishedFieldsToWorkflows < ActiveRecord::Migration[8.0]
  def change
    add_column :workflows, :published_at, :datetime
    add_reference :workflows, :published_by, foreign_key: { to_table: :users }, null: true
    add_index :workflows, :published_at, where: "published_at IS NOT NULL"
  end
end
