# frozen_string_literal: true

# CreateTools already declares `kind` and its index, so on a database built by
# replaying the migrations this one is a no-op. It is kept (rather than deleted)
# because databases created before CreateTools grew the column have it recorded
# as applied.
class AddKindToTools < ActiveRecord::Migration[7.2]
  def change
    add_column :tools, :kind, :string, null: false, default: "custom", if_not_exists: true
    add_index :tools, :kind, if_not_exists: true
  end
end
