# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261121110000_align_step_reasoning_efforts_with_the_clis")

class AlignStepReasoningEffortsWithTheClisTest < ActiveSupport::TestCase
  def step_with(runtime, model, level)
    create(:step, required_agent_runtime: runtime, preferred_model: model).tap { |step| step.update_columns(reasoning_effort: level) }
  end

  test "clears the level on Cursor and Antigravity steps and leaves other runtimes' alone" do
    cursor = step_with("cursor_cli", "composer-2.5", "low")
    antigravity = step_with("antigravity_cli", "claude-sonnet-4-6", "high")
    claude = step_with("claude_code", "claude-opus-5", "xhigh")

    migration = AlignStepReasoningEffortsWithTheClis.new
    migration.suppress_messages { migration.up }

    assert_nil cursor.reload.reasoning_effort
    assert_nil antigravity.reload.reasoning_effort
    assert_equal "xhigh", claude.reload.reasoning_effort
    assert [ cursor, antigravity, claude ].all?(&:valid?)
  end
end
