# frozen_string_literal: true

class AddNormalizedConfigToTerminalSessions < ActiveRecord::Migration[8.1]
  def change
    add_reference :terminal_sessions, :configured_agent, null: true,
                  foreign_key: { to_table: :agents, on_delete: :nullify }
    add_column :terminal_sessions, :mode, :string, default: "interactive"
    add_column :terminal_sessions, :initial_prompt, :text
  end
end
