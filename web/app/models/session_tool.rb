# frozen_string_literal: true

# Join table for TerminalSession <-> Tool relationship
class SessionTool < ApplicationRecord
  belongs_to :terminal_session
  belongs_to :tool

  validates :tool_id, uniqueness: { scope: :terminal_session_id }
end
