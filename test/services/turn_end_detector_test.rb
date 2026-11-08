# frozen_string_literal: true

require "test_helper"

class TurnEndDetectorTest < ActiveSupport::TestCase
  # `tmux capture-pane` of kiro-cli 3.0.0 (`--v3 chat`, TUI), task #208. In a 160x45 pane:
  #   turn_ended                — the agent replied and ended its turn without calling a tool
  #   turn_ended_provider_error — the turn ended on a failed model call (the proxy dropped it)
  #   turn_ended_after_nudge    — the agent answered Sessions::TurnEndNudge's message, then stopped again
  #   working                   — mid-turn, while a shell tool runs
  # The same turn end at other pane sizes, and on 2.34.0:
  #   turn_ended_80x24          — the hint line fits; the window a laptop web terminal leaves
  #   turn_ended_220x50         — a wide pane
  #   turn_ended_30x20          — a narrow pane: the placeholder, the hint and the Credits line wrap
  #   turn_ended_2_34_0_80x24   — kiro-cli 2.34.0 with `--v3`, at 80x24
  def pane(name) = file_fixture("terminal_panes/kiro_cli/#{name}.txt").read

  %w[turn_ended_80x24 turn_ended_220x50 turn_ended_30x20 turn_ended_2_34_0_80x24].each do |capture|
    test "a Kiro turn end captured as #{capture} is a turn end" do
      assert TurnEndDetector.idle?(pane(capture), agent_type: "kiro_cli")
    end
  end

  test "a draft in the wrapped prompt box of a narrow pane is not a turn end" do
    drafted = pane("turn_ended_30x20").sub(/›  ask a question or describe\n   a task ↵/, "›  please also check the\n   tests")

    refute_equal pane("turn_ended_30x20"), drafted
    refute TurnEndDetector.idle?(drafted, agent_type: "kiro_cli")
  end

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
