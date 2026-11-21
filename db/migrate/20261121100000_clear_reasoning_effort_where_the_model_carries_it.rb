# frozen_string_literal: true

# Cursor CLI and Antigravity CLI take the effort as part of the model id (task #324), so
# they offer no level any more. A level attached to the model made Cursor CLI exit and made
# Antigravity CLI quietly run its default model instead. A step that kept one would fail
# validation on its next save and on its next run's session.
class ClearReasoningEffortWhereTheModelCarriesIt < ActiveRecord::Migration[8.1]
  RUNTIMES = %w[cursor_cli antigravity_cli].freeze

  def up
    execute "UPDATE steps SET reasoning_effort = NULL " \
            "WHERE required_agent_runtime IN (#{RUNTIMES.map { |id| connection.quote(id) }.join(', ')}) " \
            "AND reasoning_effort IS NOT NULL"
  end

  def down; end
end
