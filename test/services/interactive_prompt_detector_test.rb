# frozen_string_literal: true

require "test_helper"

class InteractivePromptDetectorTest < ActiveSupport::TestCase
  # The pane a wedged Codex session shows: task #605, session 3834. `--yolo` does
  # not cover this dialog, and a non_interactive session has nobody to press Enter.
  CODEX_TRUST_PANE = <<~PANE
    root@terminal-85e5e5e154c24953c45f4c3cfa323594:/workspace# codex --yolo "$AGENT_PROMPT"
    > You are in /workspace

      Do you trust the contents of this directory? Working with untrusted contents
      comes with higher risk of prompt injection. Trusting the directory allows
      project-local config, hooks, and exec policies to load.

    › 1. Yes, continue
      2. No, quit

      Press enter to continue
  PANE

  test "detects the Codex workspace-trust prompt and names it in the message" do
    result = InteractivePromptDetector.detect(CODEX_TRUST_PANE, agent_type: "codex")

    assert result.blocked?
    assert_equal :codex_workspace_trust, result.prompt_id
    assert_match(/workspace-trust prompt/, result.message)
    assert_match(/non_interactive/, result.message)
    assert_operator result.message.length, :<=, InteractivePromptDetector::MAX_MESSAGE_LENGTH
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
      Reading task 605: Codex asks "Do you trust the contents of this directory?"
      in non_interactive mode, which wedges the step. Investigating the launch path.
    TEXT

    result = InteractivePromptDetector.detect(quoted, agent_type: "codex")

    assert_equal false, result.blocked? # rubocop:disable Minitest/RefuteFalse
  end

  test "reports healthy for ordinary output and for nothing at all" do
    assert_equal false, InteractivePromptDetector.detect("Running 42 tests...").blocked? # rubocop:disable Minitest/RefuteFalse
    assert_equal false, InteractivePromptDetector.detect(nil).blocked? # rubocop:disable Minitest/RefuteFalse
    assert_equal false, InteractivePromptDetector.detect("").blocked? # rubocop:disable Minitest/RefuteFalse
  end
end
