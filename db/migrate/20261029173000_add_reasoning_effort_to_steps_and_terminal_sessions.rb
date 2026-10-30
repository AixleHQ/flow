# frozen_string_literal: true

# The reasoning effort a step or a standalone session asks its CLI for. NULL is the
# CLI's own default, which is what every existing row keeps.
class AddReasoningEffortToStepsAndTerminalSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :steps, :reasoning_effort, :string, if_not_exists: true
    add_column :terminal_sessions, :reasoning_effort, :string, if_not_exists: true
  end
end
