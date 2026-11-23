# frozen_string_literal: true

require "test_helper"

class AgentRuntimeTest < ActiveSupport::TestCase
  test "every runtime declares its reasoning-effort levels" do
    AgentRuntime.all.each do |runtime|
      spec = runtime.reasoning_effort

      assert_kind_of Hash, spec, "#{runtime.id}: declare reasoning_effort in config/agent_runtimes.json"
      assert spec.fetch("levels").any? || spec["note"].present?,
             "#{runtime.id}: no levels, and no note telling the step editor where the effort is chosen instead"
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
    assert_equal %w[low medium high xhigh max ultra], AgentRuntime.fetch(:codex).reasoning_effort_levels("gpt-6.2-astra")
  end

  test "no runtime offers a level without an explicitly chosen model" do
    AgentRuntime.all.each do |runtime|
      assert_equal [], runtime.reasoning_effort_levels(nil), runtime.id
      assert_equal [], runtime.reasoning_effort_levels(""), runtime.id
    end
  end

  # Task #324: the vendor's catalogue says which levels each model takes (Anthropic's
  # `capabilities.effort`, Codex's `supported_reasoning_levels`, …); the registry's rule only
  # stands in when it does not say.
  test "a level the catalogue lists for the model wins over the registry, within what the CLI takes" do
    claude = AgentRuntime.fetch(:claude_code)

    assert_equal %w[low medium high max], claude.reasoning_effort_levels("claude-sonnet-4-6", offered: %w[low medium high max])
    assert_equal [], claude.reasoning_effort_levels("claude-haiku-4-5-20251001", offered: [])
    assert_equal %w[low high], AgentRuntime.fetch(:copilot_cli).reasoning_effort_levels("gpt-6-sol", offered: %w[none low high])
    assert_equal %w[low medium high xhigh max], claude.reasoning_effort_levels("claude-sonnet-4-6", offered: nil)
  end

  test "a runtime's grammar is every level its CLI takes for some model" do
    assert_equal %w[low medium high xhigh max ultra], AgentRuntime.fetch(:codex).reasoning_effort_grammar
    assert_equal %w[low high], AgentRuntime.fetch(:gemini_cli).reasoning_effort_grammar
    assert_equal [], AgentRuntime.fetch(:cursor_cli).reasoning_effort_grammar
    assert AgentRuntime.fetch(:kiro_cli).reasoning_effort?("xhigh")
    assert_not AgentRuntime.fetch(:gemini_cli).reasoning_effort?("medium")
    assert_not AgentRuntime.fetch(:antigravity_cli).reasoning_effort?("low")
  end

  # Task #324: the effort is part of a Cursor model id, and a level on top of it makes the
  # CLI refuse the model and exit.
  test "Cursor offers no level on any model" do
    cursor = AgentRuntime.fetch(:cursor_cli)

    %w[composer-2.5 claude-opus-5-5-high gpt-5.2 auto].each do |model|
      assert_equal [], cursor.reasoning_effort_levels(model), model
    end
  end

  test "reasoning_effort_levels lists every level some runtime takes" do
    assert_equal %w[low medium high xhigh max ultra], AgentRuntime.reasoning_effort_levels
  end
end
