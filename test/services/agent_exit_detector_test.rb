# frozen_string_literal: true

require "test_helper"

class AgentExitDetectorTest < ActiveSupport::TestCase
  PROMPT = "root@terminal-0123456789abcdef:/workspace#"

  # `tmux capture-pane` of an 80x24 pane: Cursor CLI 2026.11.19-f005e9d refusing
  # `composer-2.5[effort=low]` (task #324) after the launch typed by
  # AgentSessionStrategy#launch_agent_in_tmux, then Enter pressed twice on the shell.
  def cursor_rejected_pane = file_fixture("terminal_panes/cursor_cli/model_rejected.txt").read

  test "reads the exit status and the CLI's output from a pane left at the shell" do
    result = AgentExitDetector.detect(cursor_rejected_pane)

    assert_predicate result, :exited?
    assert_equal 1, result.status
    assert result.output.start_with?("Cannot use this model: composer-2.5[effort=low]. Available models: auto, gpt-5.3"),
           result.output
    assert result.output.end_with?("deepse ek-v41-flash-1017-high, deepseek-v41-flash-1017-max"), result.output
  end

  test "a CLI that exits cleanly is still an exit" do
    pane = <<~PANE
      #{PROMPT} agy --print "$(cat /tmp/.aixle-prompt)"; echo "[aixle] agent exited with status $?"
      All done.
      [aixle] agent exited with status 0
      #{PROMPT}
    PANE

    result = AgentExitDetector.detect(pane)

    assert_predicate result, :exited?
    assert_equal 0, result.status
    assert_equal "All done.", result.output
  end

  test "finds the end of a command line whose status variable wrapped across two rows" do
    pane = <<~PANE
      #{PROMPT} kiro-cli chat --trust-all-tools "$(cat /tmp/.aixle-prompt)"; echo "[aixle] agent exited with status $
      ?"
      error: unexpected argument '--bogus' found
      [aixle] agent exited with status 2
      #{PROMPT}
    PANE

    assert_equal "error: unexpected argument '--bogus' found", AgentExitDetector.detect(pane).output
  end

  test "reads the message of Antigravity's model check" do
    pane = <<~PANE
      #{PROMPT} { agy models | cut -f1 | grep -qxF -- gemini-3.7-flash-high || { echo Antigravity CLI does not offer the m
      odel gemini-3.7-flash-high on this account.; false; }; } && agy --model gemini-3.7-flash-high --dangerously-skip-perm
      issions -i "$(cat /tmp/.aixle-prompt)"; echo "[aixle] agent exited with status $?"
      Antigravity CLI does not offer the model gemini-3.7-flash-high on this account.
      [aixle] agent exited with status 1
      #{PROMPT}
    PANE

    result = AgentExitDetector.detect(pane)

    assert_equal 1, result.status
    assert_equal "Antigravity CLI does not offer the model gemini-3.7-flash-high on this account.", result.output
  end

  test "keeps the last rows of output when the command line has scrolled away" do
    output = (1..30).map { |n| "line #{n}" }
    pane = [ *output, "[aixle] agent exited with status 137", PROMPT ].join("\n")

    result = AgentExitDetector.detect(pane)

    assert_equal 137, result.status
    assert_equal (16..30).map { |n| "line #{n}" }.join(" "), result.output
  end

  test "a pane still running the CLI has not exited" do
    pane = <<~PANE
      #{PROMPT} claude; echo "[aixle] agent exited with status $?"
      ╭───────────────────────────────╮
      │ > Try "fix the failing test"  │
      ╰───────────────────────────────╯
    PANE

    assert_not_predicate AgentExitDetector.detect(pane), :exited?
  end

  # An agent may print the status line from inside its TUI, reading this repo or its
  # own launch command; the TUI's chrome below it says the CLI is still there.
  test "the status line followed by anything but shell prompts is not an exit" do
    pane = <<~PANE
      ● Bash(cat test/fixtures/files/terminal_panes/cursor_cli/model_rejected.txt)
        [aixle] agent exited with status 1
        #{PROMPT}
      ╭───────────────────────────────╮
      │ >                             │
      ╰───────────────────────────────╯
    PANE

    assert_not_predicate AgentExitDetector.detect(pane), :exited?
  end

  test "the typed command line alone is not an exit" do
    pane = <<~PANE
      #{PROMPT} agent --force --disable-auto-update "$(cat /tmp/.aixle-prompt)"; echo "[aixle] agent exited with status $?"
    PANE

    assert_not_predicate AgentExitDetector.detect(pane), :exited?
  end

  test "an empty pane has not exited" do
    assert_not_predicate AgentExitDetector.detect(nil), :exited?
    assert_not_predicate AgentExitDetector.detect(""), :exited?
  end
end
