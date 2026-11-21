# frozen_string_literal: true

# Cursor CLI and Antigravity CLI take the effort only through the model id (task #324): a
# level attached to the model made Cursor exit and made Antigravity quietly run its default
# model, so neither takes a level any more. A step that kept one would fail validation on
# its next save and on its next run's session.
class AlignStepReasoningEffortsWithTheClis < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE steps SET reasoning_effort = NULL " \
            "WHERE required_agent_runtime IN ('cursor_cli', 'antigravity_cli') AND reasoning_effort IS NOT NULL"
  end

  def down; end
end
