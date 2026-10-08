# frozen_string_literal: true

require "test_helper"

class InteractivePromptDetectorTest < ActiveSupport::TestCase
  # `tmux capture-pane` of Codex 0.161.0 parked on its folder-trust dialog in an
  # 80x24 pane (tmux's detached default), the TUI running in-process. `--yolo` does
  # not cover this dialog, and a non_interactive session has nobody to press Enter.
  CODEX_TRUST_PANE = <<~PANE

      Folder access
      /workspace

      Trust this folder? Codex can read, edit, and run files here, subject to your
      permission settings. Folder settings can run code automatically, even
      without a model request. Continue only if you trust these files. Your trust
      decision will be saved.

    › 1. Trust and continue
      2. Quit

      enter continue · esc quit
  PANE

  # The same CLI's idle chat screen, which is what a Codex pane ends on whenever the
  # session got past startup.
  CODEX_CHAT_SCREEN = <<~PANE

      >_ OpenAI Codex (v0.161.0)
         /workspace

    › Ask Codex to do anything

      ? for shortcuts
  PANE

  test "detects the Codex workspace-trust prompt and names it in the message" do
    result = InteractivePromptDetector.detect(CODEX_TRUST_PANE, agent_type: "codex")

    assert result.blocked?
    assert_equal :codex_workspace_trust, result.prompt_id
    assert_match(/workspace-trust prompt/, result.message)
    assert_match(/Trust this folder\?/, result.message)
    assert_match(/non_interactive/, result.message)
    assert_operator result.message.length, :<=, InteractivePromptDetector::MAX_MESSAGE_LENGTH
  end

  # Attached to Codex's background server the dialog offers to go back to the agent
  # list instead of quitting.
  test "detects the prompt when the TUI runs on the background server" do
    daemon_pane = CODEX_TRUST_PANE.sub("2. Quit", "2. Back to Agent Command Center").sub("esc quit", "esc back")

    result = InteractivePromptDetector.detect(daemon_pane, agent_type: "codex")

    assert result.blocked?
  end

  # A narrow pane wraps the disclosure differently and the dialog drops its blank
  # rows (codex-rs/tui/src/onboarding/snapshots/…__long_checkout_40x13.snap).
  test "detects the prompt wrapped to a narrow pane" do
    narrow = <<~PANE
        Folder access
        /workspace
        Trust this folder? Codex can read,
        edit, and run files here, subject to
        your permission settings. Folder
        settings can run code automatically,
        even without a model request.
        Continue only if you trust these
        files. Your trust decision will be
        saved.
      › 1. Trust and continue
        2. Quit
        enter continue · esc quit
    PANE

    result = InteractivePromptDetector.detect(narrow, agent_type: "codex")

    assert result.blocked?
  end

  test "detects the prompt when the agent_type is unknown to the caller" do
    result = InteractivePromptDetector.detect(CODEX_TRUST_PANE)

    assert result.blocked?
  end

  test "ignores a signature another agent produced" do
    result = InteractivePromptDetector.detect(CODEX_TRUST_PANE, agent_type: "claude_code")

    assert_equal false, result.blocked? # rubocop:disable Minitest/RefuteFalse
  end

  # The single most dangerous false positive: the phrase travels through bug
  # reports, task descriptions and this very repo's docs, so an agent that prints
  # the incident it is investigating must not be killed for quoting it.
  test "does not fire on the prompt text quoted without the dialog around it" do
    quoted = <<~TEXT
      Reading task 605: Codex asks "Trust this folder?" and waits on "Trust and continue",
      which a non_interactive step cannot press. Investigating the launch path.
    TEXT

    result = InteractivePromptDetector.detect(quoted, agent_type: "codex")

    assert_equal false, result.blocked? # rubocop:disable Minitest/RefuteFalse
  end

  # The dangerous shape the phrase-only test above does not cover: the *complete*
  # dialog, printed verbatim by a session that then keeps working. The pane no longer
  # ends on the dialog but on Codex's own composer, so the session is not on it.
  test "does not fire on the complete dialog quoted before ordinary agent output" do
    investigating = <<~TEXT
      #{CODEX_TRUST_PANE}
      That is the wedge from task 605. Reading app/services/agents/codex_adapter.rb
      to check how the launch command grants trust.
      #{CODEX_CHAT_SCREEN}
    TEXT

    result = InteractivePromptDetector.detect(investigating, agent_type: "codex")

    assert_equal false, result.blocked? # rubocop:disable Minitest/RefuteFalse
  end

  # capture-pane hands over 1,000 lines of scrollback. A dialog that scrolled out of
  # sight long ago must not be read as the screen the CLI is blocked on now.
  test "does not fire on a dialog left far behind in the scrollback" do
    scrolled_away = CODEX_TRUST_PANE + Array.new(60) { |i| "  ✓ test case #{i} passed" }.join("\n")

    result = InteractivePromptDetector.detect(scrolled_away, agent_type: "codex")

    assert_equal false, result.blocked? # rubocop:disable Minitest/RefuteFalse
  end

  # tmux pads capture-pane output to the pane height, so the real wedged pane arrives
  # with trailing blank rows after the dialog — they are padding, not output.
  test "detects the prompt through the blank rows tmux pads the pane with" do
    result = InteractivePromptDetector.detect("#{CODEX_TRUST_PANE}\n\n\n\n", agent_type: "codex")

    assert result.blocked?
  end

  # The pane can be captured in the instant before the key hint renders, leaving the
  # last option as the final line.
  test "detects the prompt when the pane ends on the last dialog option" do
    without_hint = CODEX_TRUST_PANE.sub(/\n\s*enter continue · esc quit\n/, "\n")

    result = InteractivePromptDetector.detect(without_hint, agent_type: "codex")

    assert result.blocked?
  end

  test "reports healthy for ordinary output and for nothing at all" do
    assert_equal false, InteractivePromptDetector.detect(CODEX_CHAT_SCREEN, agent_type: "codex").blocked? # rubocop:disable Minitest/RefuteFalse
    assert_equal false, InteractivePromptDetector.detect("Running 42 tests...").blocked? # rubocop:disable Minitest/RefuteFalse
    assert_equal false, InteractivePromptDetector.detect(nil).blocked? # rubocop:disable Minitest/RefuteFalse
    assert_equal false, InteractivePromptDetector.detect("").blocked? # rubocop:disable Minitest/RefuteFalse
  end
end
