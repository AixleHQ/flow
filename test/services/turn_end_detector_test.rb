# frozen_string_literal: true

require "test_helper"

class TurnEndDetectorTest < ActiveSupport::TestCase
  # `tmux capture-pane` of kiro-cli 3.0.0 (`--v3 chat`, TUI) in a 160x45 pane, task #208:
  #   turn_ended                — the agent replied and ended its turn without calling a tool
  #   turn_ended_provider_error — the turn ended on a failed model call (the proxy dropped it)
  #   turn_ended_after_nudge    — the agent answered Sessions::TurnEndNudge's message, then stopped again
  #   working                   — mid-turn, while a shell tool runs
  def pane(name) = file_fixture("terminal_panes/kiro_cli/#{name}.txt").read

  test "a Kiro turn that ended at the prompt is a turn end" do
    assert TurnEndDetector.idle?(pane("turn_ended"), agent_type: "kiro_cli")
  end

  test "a Kiro turn ended by a provider error is a turn end too" do
    assert TurnEndDetector.idle?(pane("turn_ended_provider_error"), agent_type: "kiro_cli")
  end

  test "the turn after a reminder ends on the same screen" do
    assert TurnEndDetector.idle?(pane("turn_ended_after_nudge"), agent_type: "kiro_cli")
  end

  test "a working Kiro is not at a turn end" do
    refute TurnEndDetector.idle?(pane("working"), agent_type: "kiro_cli")
  end

  test "a draft in the prompt box is a person typing, not a turn end" do
    drafted = pane("turn_ended").sub("ask a question or describe a task ↵", "please also check the")

    refute TurnEndDetector.idle?(drafted, agent_type: "kiro_cli")
  end

  test "the prompt before any turn has finished is not a turn end" do
    started = pane("turn_ended").lines.reject { |line| line.include?("▸ Credits:") }.join

    refute TurnEndDetector.idle?(started, agent_type: "kiro_cli")
  end

  test "a turn end quoted in the scrollback does not count once the agent has moved on" do
    moved_on = "#{pane('turn_ended')}#{pane('working')}"

    refute TurnEndDetector.idle?(moved_on, agent_type: "kiro_cli")
  end

  test "runtimes without a measured signature are never at a turn end" do
    refute TurnEndDetector.idle?(pane("turn_ended"), agent_type: "claude_code")
    refute TurnEndDetector.idle?(pane("turn_ended"), agent_type: nil)
  end

  test "an empty pane is not a turn end" do
    refute TurnEndDetector.idle?("", agent_type: "kiro_cli")
    refute TurnEndDetector.idle?(nil, agent_type: "kiro_cli")
  end
end
