# frozen_string_literal: true

class AddKindToTools < ActiveRecord::Migration[7.2]
  def change
    add_column :tools, :kind, :string, null: false, default: "custom"
    add_index :tools, :kind
  end
end
