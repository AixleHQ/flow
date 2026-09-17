# frozen_string_literal: true

# tool_results.terminal_session_id is ON DELETE RESTRICT, but User has
# `has_many :terminal_sessions, dependent: :destroy`. Permanent user deletion
# destroys the user's sessions, and any tool_result referencing them blocks the
# cascade with InvalidForeignKey. The column is already nullable, so flipping
# the FK to :nullify is safe and keeps tool-result history intact.
class NullifyToolResultsTerminalSessionFk < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :tool_results, :terminal_sessions
    add_foreign_key :tool_results, :terminal_sessions, on_delete: :nullify
  end

  def down
    remove_foreign_key :tool_results, :terminal_sessions
    add_foreign_key :tool_results, :terminal_sessions
  end
end
