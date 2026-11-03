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

  test "a model no rule names takes the runtime's own levels" do
    assert_equal %w[low medium high xhigh max], AgentRuntime.fetch(:kiro_cli).reasoning_effort_levels("claude-opus-5.5")
    assert_equal %w[low high], AgentRuntime.fetch(:gemini_cli).reasoning_effort_levels("gemini-3-pro")
  end

  test "a model rule replaces the runtime's levels, first match wins" do
    kiro = AgentRuntime.fetch(:kiro_cli)

    assert_equal %w[low medium high max], kiro.reasoning_effort_levels("claude-sonnet-4.6")
    assert_equal [], kiro.reasoning_effort_levels("auto")
    assert_equal [], kiro.reasoning_effort_levels("claude-haiku-4.5")
    assert_equal %w[low medium high xhigh max], kiro.reasoning_effort_levels("claude-opus-5.5")
    assert_equal %w[low medium high xhigh max ultra], AgentRuntime.fetch(:codex).reasoning_effort_levels("gpt-6-sol")
  end

  test "no runtime offers a level without an explicitly chosen model" do
    AgentRuntime.all.each do |runtime|
      assert_equal [], runtime.reasoning_effort_levels(nil), runtime.id
      assert_equal [], runtime.reasoning_effort_levels(""), runtime.id
      assert_not runtime.reasoning_effort?("low", nil), runtime.id
    end
    assert_equal %w[low medium high], AgentRuntime.fetch(:cursor_cli).reasoning_effort_levels("claude-opus-4-8")
  end

  test "reasoning_effort_levels lists every level some runtime takes" do
    assert_equal %w[low medium high xhigh max ultra], AgentRuntime.reasoning_effort_levels
  end
end
