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

  # `tmux capture-pane` of Claude Code 2.1.294 in a 120x30 pane while an MCP server on the
  # 2025-11-25 protocol answers a tool call with a URL-mode elicitation and never reports
  # completion. Still on screen after 2.5 minutes: there is no timeout.
  CLAUDE_MCP_URL_PANE = <<~PANE
     ▐▛███▛█   Claude Code v2.1.294
    ▝▜██████▀  Opus 5.5 · API Usage Billing
     ▝▝   ▝▝   /workspace
    ❯ Call the login tool, then say done.
    ● Calling urlmock · 22s…
    #{"─" * 120}
      MCP server “urlmock” wants to open a URL
      Sign in to Example to let the agent read your issues.
      https://auth.example.com/oauth/authorize?client_id=urlmock&state=abc123
      ❯ Accept    Decline
      Esc to cancel · ←/→ to switch
  PANE

  # The same CLI and server when the elicitation is a form instead of a URL.
  CLAUDE_MCP_FORM_PANE = <<~PANE
     ▐▛███▛█   Claude Code v2.1.294
    ▝▜██████▀  Opus 5.5 · API Usage Billing
     ▝▝   ▝▝   /workspace
    ❯ Call the login tool, then say done.
    ● Calling urlmock · 22s…
    #{"─" * 120}
      MCP server “urlmock” requests your input
      Which Example project should the agent use?
      ❯ * Project: Type something…
        Accept    Decline
      Esc to cancel · ↑/↓ to navigate · Backspace to unset
  PANE

  # Claude Code's idle screen after the turn ended.
  CLAUDE_CHAT_SCREEN = <<~PANE
    ● done
    ✻ Worked for 0s · done 2:11 PM
    #{"─" * 120}
    ❯
    #{"─" * 120}
      ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents
  PANE

  # `tmux capture-pane` of Claude Code 2.1.310 in a 120x30 pane, API-key billed, once the
  # session's cost crossed $5 and with hasAcknowledgedCostThreshold absent from
  # ~/.claude.json. The notice waits for a keypress.
  CLAUDE_COST_THRESHOLD_PANE = <<~PANE
     ▐▛███▛█   Claude Code v2.1.310
    ▝▜██████▀  Sonnet 4.5 · API Usage Billing
     ▝▝   ▝▝   /workspace
    ❯ Say done.
    ● done
    ✻ Sautéed for 0s · done 3:13 PM
    #{"─" * 120}
      You've spent $5 on the Anthropic API this session.

      Learn more about how to monitor your spending:
      https://code.claude.com/docs/en/costs

      ❯ 1. Got it, thanks!

      Enter to confirm · Esc to cancel
  PANE

  # `tmux capture-pane` of Kiro CLI 2.34.0 (`--v3`, TUI) in a 160x45 pane after an MCP
  # tool failed 7 times in a row. The session's steering said nobody can answer; the
  # dialog was still on screen 4 minutes later.
  KIRO_QUESTION_PANE = <<~PANE
    • flaky_check
        ╰ attempt=7
        MCP tool error: ERROR: upstream timeout (503)

    #{"─" * 160}
     Trust All Tools active, confirmations are off · /quit to exit
    #{"─" * 160}
     Question
     I've been trying to use "tool_call(aixle-tools::flaky_check)" but it's failed 7 times in a row. I'm clearly stuck in a loop.

     What would you like me to do?

     ❯ 1. Cancel
       2. Keep Iterating
       Type a different answer…
    #{"─" * 160}
       esc to cancel · ↑↓ to navigate · ↵ to submit
  PANE

  # The same session once someone chose Keep Iterating: the agent is working again.
  KIRO_WORKING_SCREEN = <<~PANE
      › Keep Iterating
    • flaky_check
        ╰ attempt=8
        MCP tool error: ERROR: upstream timeout (503)
    ᗥ Thinking... (esc to cancel)
    #{"─" * 160}
     Trust All Tools active, confirmations are off · /quit to exit
    #{"─" * 160}
    Default · auto · ◔ 3%                                                                                                                                 /workspace

    ›  Kiro is working · 30s · Type to steer · Ctrl+S to queue
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

  test "detects Claude Code waiting on an MCP server's URL prompt" do
    result = InteractivePromptDetector.detect(CLAUDE_MCP_URL_PANE, agent_type: "claude_code")

    assert result.blocked?
    assert_equal :claude_mcp_url_prompt, result.prompt_id
    assert_match(/wants to open a URL/, result.message)
    assert_operator result.message.length, :<=, InteractivePromptDetector::MAX_MESSAGE_LENGTH
  end

  # A 60-column pane wraps the URL onto a second line; the title and options stay whole.
  test "detects the MCP URL prompt in a narrow pane" do
    narrow = CLAUDE_MCP_URL_PANE
      .sub("─" * 120, "─" * 60)
      .sub("client_id=urlmock&state=abc123", "client_id=urlmo\n  ck&state=abc123")

    result = InteractivePromptDetector.detect(narrow, agent_type: "claude_code")

    assert_equal :claude_mcp_url_prompt, result.prompt_id
  end

  test "detects Claude Code waiting on an MCP server's input form" do
    result = InteractivePromptDetector.detect(CLAUDE_MCP_FORM_PANE, agent_type: "claude_code")

    assert result.blocked?
    assert_equal :claude_mcp_input_form, result.prompt_id
    assert_match(/requests your input/, result.message)
  end

  # Declined (or answered) and back at the composer: the dialog is history, not the
  # screen the session is on.
  test "does not fire once Claude Code has moved past the MCP prompt" do
    moved_on = "#{CLAUDE_MCP_URL_PANE}#{CLAUDE_CHAT_SCREEN}"

    result = InteractivePromptDetector.detect(moved_on, agent_type: "claude_code")

    assert_equal false, result.blocked? # rubocop:disable Minitest/RefuteFalse
  end

  test "does not apply the Claude Code MCP signatures to another agent" do
    result = InteractivePromptDetector.detect(CLAUDE_MCP_URL_PANE, agent_type: "codex")

    assert_equal false, result.blocked? # rubocop:disable Minitest/RefuteFalse
  end

  test "detects Claude Code waiting on its cost-threshold notice and names it" do
    result = InteractivePromptDetector.detect(CLAUDE_COST_THRESHOLD_PANE, agent_type: "claude_code")

    assert result.blocked?
    assert_equal :claude_cost_threshold, result.prompt_id
    assert_match(/cost-threshold notice/, result.message)
    assert_match(/You've spent \$5 on the Anthropic API this session/, result.message)
    assert_operator result.message.length, :<=, InteractivePromptDetector::MAX_MESSAGE_LENGTH
  end

  test "does not fire once Claude Code has moved past the cost-threshold notice" do
    moved_on = "#{CLAUDE_COST_THRESHOLD_PANE}#{CLAUDE_CHAT_SCREEN}"

    result = InteractivePromptDetector.detect(moved_on, agent_type: "claude_code")

    assert_equal false, result.blocked? # rubocop:disable Minitest/RefuteFalse
  end

  # The notice's footer is shared by every Claude Code select dialog; without the
  # notice's own text above it, the pane is some other dialog.
  test "does not take another Claude Code dialog with the same footer for the notice" do
    other = CLAUDE_COST_THRESHOLD_PANE
      .sub("You've spent $5 on the Anthropic API this session.", "Choose a model")
      .sub("Got it, thanks!", "Sonnet")

    result = InteractivePromptDetector.detect(other, agent_type: "claude_code")

    assert_equal false, result.blocked? # rubocop:disable Minitest/RefuteFalse
  end

  test "does not apply the cost-threshold signature to another agent" do
    result = InteractivePromptDetector.detect(CLAUDE_COST_THRESHOLD_PANE, agent_type: "kiro_cli")

    assert_equal false, result.blocked? # rubocop:disable Minitest/RefuteFalse
  end

  test "detects Kiro waiting on its own Question dialog" do
    result = InteractivePromptDetector.detect(KIRO_QUESTION_PANE, agent_type: "kiro_cli")

    assert result.blocked?
    assert_equal :kiro_question, result.prompt_id
    assert_match(/"Question" dialog/, result.message)
    assert_operator result.message.length, :<=, InteractivePromptDetector::MAX_MESSAGE_LENGTH
  end

  test "does not fire once Kiro has moved past its Question dialog" do
    moved_on = "#{KIRO_QUESTION_PANE}#{KIRO_WORKING_SCREEN}"

    result = InteractivePromptDetector.detect(moved_on, agent_type: "kiro_cli")

    assert_equal false, result.blocked? # rubocop:disable Minitest/RefuteFalse
  end

  test "does not apply the Kiro signature to another agent" do
    result = InteractivePromptDetector.detect(KIRO_QUESTION_PANE, agent_type: "claude_code")

    assert_equal false, result.blocked? # rubocop:disable Minitest/RefuteFalse
  end

  test "reports healthy for ordinary output and for nothing at all" do
    assert_equal false, InteractivePromptDetector.detect(CODEX_CHAT_SCREEN, agent_type: "codex").blocked? # rubocop:disable Minitest/RefuteFalse
    assert_equal false, InteractivePromptDetector.detect(CLAUDE_CHAT_SCREEN, agent_type: "claude_code").blocked? # rubocop:disable Minitest/RefuteFalse
    assert_equal false, InteractivePromptDetector.detect("Running 42 tests...").blocked? # rubocop:disable Minitest/RefuteFalse
    assert_equal false, InteractivePromptDetector.detect(nil).blocked? # rubocop:disable Minitest/RefuteFalse
    assert_equal false, InteractivePromptDetector.detect("").blocked? # rubocop:disable Minitest/RefuteFalse
  end
end
