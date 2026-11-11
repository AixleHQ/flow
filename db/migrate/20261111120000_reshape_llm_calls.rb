# frozen_string_literal: true

# llm_calls becomes the canonical per-call record (docs/design/insights-usage-export.md §3).
# Its rows are derived from usage_statistics.events_data, so any written under the old
# shape are dropped rather than converted; `bin/rails llm_calls:backfill` rebuilds them.
class ReshapeLlmCalls < ActiveRecord::Migration[8.1]
  TOKEN_COLUMNS = %i[input_tokens output_tokens cache_read_tokens cache_write_tokens].freeze

  def up
    execute "DELETE FROM llm_calls"

    add_column :llm_calls, :uid, :uuid, null: false, default: -> { "gen_random_uuid()" }
    add_column :llm_calls, :event_index, :integer, null: false
    add_column :llm_calls, :provider, :string, null: false
    add_column :llm_calls, :cost_basis, :string, null: false
    add_column :llm_calls, :granularity, :string, null: false
    add_column :llm_calls, :duration_ms, :integer

    TOKEN_COLUMNS.each do |column|
      change_column_default :llm_calls, column, from: 0, to: nil
      change_column_null :llm_calls, column, true
    end
    change_column_default :llm_calls, :total_cents_precise, from: "0.0", to: nil
    change_column_null :llm_calls, :total_cents_precise, true

    add_index :llm_calls, :uid, unique: true
    add_index :llm_calls, %i[terminal_session_id event_index], unique: true
  end

  def down
    execute "DELETE FROM llm_calls"

    remove_index :llm_calls, %i[terminal_session_id event_index]
    remove_index :llm_calls, :uid

    change_column_null :llm_calls, :total_cents_precise, false
    change_column_default :llm_calls, :total_cents_precise, from: nil, to: "0.0"
    TOKEN_COLUMNS.each do |column|
      change_column_null :llm_calls, column, false
      change_column_default :llm_calls, column, from: nil, to: 0
    end

    remove_column :llm_calls, :duration_ms
    remove_column :llm_calls, :granularity
    remove_column :llm_calls, :cost_basis
    remove_column :llm_calls, :provider
    remove_column :llm_calls, :event_index
    remove_column :llm_calls, :uid
  end
end
