# frozen_string_literal: true

class AddTokenBreakdownToUsageStatistics < ActiveRecord::Migration[8.1]
  def change
    change_table :usage_statistics, bulk: true do |t|
      # Detailed token breakdown from Cursor Dashboard API
      t.bigint :input_tokens, default: 0, null: false
      t.bigint :output_tokens, default: 0, null: false
      t.bigint :cache_write_tokens, default: 0, null: false
      t.bigint :cache_read_tokens, default: 0, null: false

      # Precise cost from API (float cents, e.g. 170.705267)
      t.decimal :total_cents_precise, precision: 12, scale: 6, default: 0
      t.decimal :cursor_token_fee_cents, precision: 12, scale: 6, default: 0

      # Model used (e.g. "claude-4.6-opus-max-thinking")
      t.string :model

      # Data source: cursor_api, estimated, hook
      t.string :source, default: "unknown", null: false

      # How many API events were matched to this session
      t.integer :events_count, default: 0, null: false

      # Raw matched events for debugging/auditing
      t.jsonb :events_data, default: []
    end
  end
end
