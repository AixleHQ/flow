# frozen_string_literal: true

class AddPayloadToMemoryRetrievals < ActiveRecord::Migration[8.1]
  def change
    add_column :memory_retrievals, :payload, :jsonb, null: false, default: {}
  end
end
