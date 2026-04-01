# frozen_string_literal: true

class ChangeTokenColumnsToBigintOnTerminalSessions < ActiveRecord::Migration[7.1]
  def up
    change_column :terminal_sessions, :total_tokens, :bigint, default: 0, null: false
    change_column :terminal_sessions, :input_tokens, :bigint, default: 0, null: false
    change_column :terminal_sessions, :output_tokens, :bigint, default: 0, null: false
    change_column :terminal_sessions, :cache_read_tokens, :bigint, default: 0, null: false
    change_column :terminal_sessions, :cache_write_tokens, :bigint, default: 0, null: false
    change_column :terminal_sessions, :cost_cents, :bigint, default: 0, null: false
  end

  def down
    change_column :terminal_sessions, :total_tokens, :integer, default: 0, null: false
    change_column :terminal_sessions, :input_tokens, :integer, default: 0, null: false
    change_column :terminal_sessions, :output_tokens, :integer, default: 0, null: false
    change_column :terminal_sessions, :cache_read_tokens, :integer, default: 0, null: false
    change_column :terminal_sessions, :cache_write_tokens, :integer, default: 0, null: false
    change_column :terminal_sessions, :cost_cents, :integer, default: 0, null: false
  end
end
