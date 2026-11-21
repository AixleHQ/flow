# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261121100000_align_step_reasoning_efforts_with_the_clis")

class AlignStepReasoningEffortsWithTheClisTest < ActiveSupport::TestCase
  def step_with(runtime, model, level)
    create(:step, required_agent_runtime: runtime, preferred_model: model).tap do |step|
      step.update_columns(reasoning_effort: level)
    end
  end

  test "each level a CLI does not take becomes what the CLI ran instead, and every step validates" do
    steps = {
      %w[cursor_cli composer-2.5 low] => nil,
      %w[antigravity_cli claude-sonnet-4-6 high] => nil,
      %w[claude_code claude-haiku-4-5-20251001 low] => nil,
      %w[claude_code claude-opus-4-5-20251101 max] => "high",
      %w[claude_code claude-opus-4-5-20251101 medium] => "medium",
      %w[claude_code claude-sonnet-4-6 xhigh] => "high",
      %w[claude_code claude-sonnet-4-6 max] => "max",
      %w[claude_code claude-opus-5 xhigh] => "xhigh",
      %w[kiro_cli glm-5 high] => nil,
      %w[kiro_cli claude-opus-4.6 xhigh] => "high",
      %w[kiro_cli grok-4.7 max] => "high",
      %w[kiro_cli claude-opus-5.5 max] => "max",
      %w[codex gpt-6-sol ultra] => "ultra"
    }.to_h { |(runtime, model, level), expected| [ step_with(runtime, model, level), expected ] }

    migration = AlignStepReasoningEffortsWithTheClis.new
    migration.suppress_messages { migration.up }

    steps.each do |step, expected|
      step.reload
      label = "#{step.required_agent_runtime} #{step.preferred_model}"
      expected.nil? ? assert_nil(step.reasoning_effort, label) : assert_equal(expected, step.reasoning_effort, label)
      assert_predicate step, :valid?, "#{step.preferred_model}: #{step.errors.full_messages.to_sentence}"
    end
  end
end
