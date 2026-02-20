# frozen_string_literal: true

class AddSessionOutputFieldsToAssets < ActiveRecord::Migration[8.1]
  def change
    add_reference :assets, :terminal_session, null: true,
                  foreign_key: { on_delete: :nullify }, index: true
    add_column :assets, :status, :string, null: false, default: "active"
    add_column :assets, :reviewed_at, :datetime
    add_index :assets, :status
  end
end
