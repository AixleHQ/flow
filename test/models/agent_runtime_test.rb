# frozen_string_literal: true

require "test_helper"

class AgentRuntimeTest < ActiveSupport::TestCase
  test "every runtime declares its reasoning-effort levels" do
    AgentRuntime.all.each do |runtime|
      spec = runtime.reasoning_effort

      assert_kind_of Hash, spec, "#{runtime.id}: declare reasoning_effort in config/agent_runtimes.json"
      assert spec.fetch("levels").any?, "#{runtime.id}: no levels"
      spec.fetch("models").each { |rule| Regexp.new(rule.fetch("match")) }
    end
  end

  test "the levels are the runtime's own, for its default model" do
    assert_equal %w[low medium high xhigh max], AgentRuntime.fetch(:kiro_cli).reasoning_effort_levels
    assert_equal %w[low high], AgentRuntime.fetch(:gemini_cli).reasoning_effort_levels
  end

  test "a model rule replaces the runtime's levels, first match wins" do
    kiro = AgentRuntime.fetch(:kiro_cli)

    assert_equal %w[low medium high max], kiro.reasoning_effort_levels("claude-sonnet-4.6")
    assert_equal [], kiro.reasoning_effort_levels("auto")
    assert_equal [], kiro.reasoning_effort_levels("claude-haiku-4.5")
    assert_equal %w[low medium high xhigh max], kiro.reasoning_effort_levels("claude-opus-5.5")
    assert_equal %w[low medium high xhigh max ultra], AgentRuntime.fetch(:codex).reasoning_effort_levels("gpt-6-sol")
  end

  test "a runtime that needs a model offers nothing without one" do
    cursor = AgentRuntime.fetch(:cursor_cli)

    assert_equal [], cursor.reasoning_effort_levels(nil)
    assert_equal %w[low medium high], cursor.reasoning_effort_levels("claude-opus-4-8")
  end

  test "reasoning_effort_levels lists every level some runtime takes" do
    assert_equal %w[low medium high xhigh max ultra], AgentRuntime.reasoning_effort_levels
  end
end
