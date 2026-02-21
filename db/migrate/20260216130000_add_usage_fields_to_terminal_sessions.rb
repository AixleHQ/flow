# frozen_string_literal: true

class AddUsageFieldsToTerminalSessions < ActiveRecord::Migration[8.1]
  def change
    change_table :terminal_sessions, bulk: true do |t|
      t.integer :total_tokens, default: 0, null: false
      t.integer :input_tokens, default: 0, null: false
      t.integer :output_tokens, default: 0, null: false
      t.integer :cache_read_tokens, default: 0, null: false
      t.integer :cache_write_tokens, default: 0, null: false
      t.integer :cost_cents, default: 0, null: false
      t.string :models, array: true, default: [], null: false
    end
  end
end
