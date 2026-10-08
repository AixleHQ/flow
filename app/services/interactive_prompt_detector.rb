# frozen_string_literal: true

# InteractivePromptDetector
#
# Finds CLI prompts — at startup or mid-tool-call — in live terminal output that a
# `non_interactive` session can never answer. Such a session does not fail and does
# not finish: the CLI sits on a TTY dialog, the terminal produces no further bytes,
# the step stays `running` and the terminal session stays `ready` until a human
# notices (task #605 — Codex's workspace-trust dialog wedged run 3190 / step run
# 3476 / session 3834 for ~52 minutes on zero tokens).
#
# Detection is deliberately conservative, because the action it triggers is
# destructive. Two independent conditions have to hold:
#
#   1. every marker of a signature is present, and
#   2. the dialog is the screen the CLI is *currently* blocked on — all markers
#      sit inside the pane's trailing block and its last nonblank line is the
#      dialog's own footer.
#
# The prompt text also appears in bug reports, task descriptions and this repo's
# docs, which an agent may legitimately print to its own terminal — the caller
# hands over 1,000 lines of scrollback, so matching anywhere in it would kill
# exactly the session investigating the incident, even long after that session had
# moved past startup. A pane whose last word is not the dialog's is a pane whose
# agent is still producing output, so it is not wedged on the dialog.
#
# Sibling of QuotaErrorDetector — same shape, same caller
# (Activities::Workflow::ScanQuotaErrorsActivity), different blocker.
class InteractivePromptDetector
  MAX_MESSAGE_LENGTH = 500

  # How much of the pane's tail counts as "the current screen". The caller captures
  # up to 1,000 scrollback lines; a rendered dialog spans ~10 of them, so this is
  # generous enough for banners and wrapping around it while still excluding the
  # scrollback where a quoted copy of the same text would live.
  TAIL_LINES = 40

  # Each signature: which agents can produce it, the markers that must ALL appear
  # in the pane's trailing block, the footer the pane has to *end* on, and the
  # diagnostic that goes on the failed session. The message names the prompt and the
  # platform-side setting that is supposed to prevent it, so the operator reading a
  # failed step does not have to rediscover the cause.
  SIGNATURES = [
    {
      # Codex 0.156.0+ (codex-rs/tui/src/onboarding/trust_directory.rs). 0.155 and
      # earlier asked "Do you trust the contents of this directory?"; every image
      # since #303 pins 0.156.1 or newer, so that wording is not matched.
      id: :codex_workspace_trust,
      agent_types: %w[codex],
      markers: [
        /Trust this folder\?/i,
        /Trust and continue/i
      ],
      # The last thing a blocked pane shows: the key hint, or — when the pane is
      # captured before that line renders — the dialog's final option. The cancel
      # choice depends on where the TUI runs: "Quit" / "esc quit" in-process, "Back to
      # Agent Command Center" / "esc back" when attached to the background server.
      # Anchored at the start of the line so prose that merely mentions the phrase
      # mid-sentence does not qualify as a footer.
      footer: /\A\s*(?:enter continue\b.*\besc (?:quit|back)\b|[›>]?\s*2\.\s+(?:Quit|Back to Agent Command Center)\z)/i,
      message: "Codex is blocked on the workspace-trust prompt " \
               '("Trust this folder?"), which a non_interactive ' \
               "session cannot answer. Trust is granted both on the launch command " \
               "(Agents::CodexAdapter#cli_trust_flag) and by the [projects.\"<workspace>\"] " \
               "entry in ~/.codex/config.toml — both were missing for this container."
    },
    {
      # Claude Code 2.1.287+ shows this when an MCP server (2025-11-25 protocol) asks
      # the user to open a link mid-tool-call, typically to sign in; 2.1.274 declined
      # such requests on its own. It has no timeout: the tool call waits for a person.
      id: :claude_mcp_url_prompt,
      agent_types: %w[claude_code],
      markers: [
        /MCP server\s[\s\S]{1,120}?\swants to open a URL/,
        /Accept\s+Decline/
      ],
      footer: %r{\A\s*Esc to cancel · ←/→ to switch\z},
      message: "Claude Code is blocked on an MCP server's URL prompt " \
               '("MCP server … wants to open a URL"), which a non_interactive session ' \
               "cannot answer: the server asked a person to open a link, usually to sign " \
               "in, and the tool call waits for Accept or Decline. Sign in to that MCP " \
               "server outside the step, or run the step interactively."
    },
    {
      # The form variant of the same MCP elicitation (2.1.294 renders it; 2.1.274
      # declined it on its own). The footer's hints depend on the fields, so only its
      # fixed start is matched.
      id: :claude_mcp_input_form,
      agent_types: %w[claude_code],
      markers: [
        /MCP server\s[\s\S]{1,120}?\srequests your input/,
        /Accept\s+Decline/
      ],
      footer: %r{\A\s*Esc to cancel · ↑/↓ to navigate\b},
      message: "Claude Code is blocked on an MCP server's input form " \
               '("MCP server … requests your input"), which a non_interactive session ' \
               "cannot fill in: the tool call waits for a person to Accept or Decline. " \
               "Give the MCP server what it asks for in its configuration, or run the " \
               "step interactively."
    }
  ].freeze

  Result = Struct.new(:blocked, :prompt_id, :message, keyword_init: true) do
    def blocked? = blocked
  end

  # @param text [String, nil] rendered terminal output (tmux capture-pane)
  # @param agent_type [String, nil] session agent_type; when given, only signatures
  #   declared for that agent are considered
  # @return [Result]
  def self.detect(text, agent_type: nil)
    return Result.new(blocked: false) if text.blank?

    tail = current_screen(text)
    return Result.new(blocked: false) if tail.empty?

    tail_text = tail.join("\n")

    SIGNATURES.each do |signature|
      next if agent_type.present? && signature[:agent_types].exclude?(agent_type.to_s)
      # Cheapest and most selective check first: a pane that does not end on the
      # dialog belongs to a session that is still talking, whatever its scrollback says.
      next unless signature[:footer].match?(tail.last)
      next unless signature[:markers].all? { |marker| tail_text.match?(marker) }

      return Result.new(
        blocked: true,
        prompt_id: signature[:id],
        message: truncate("Session terminated: #{signature[:message]}")
      )
    end

    Result.new(blocked: false)
  end

  # The pane's trailing block: the last TAIL_LINES nonblank lines. tmux pads
  # capture-pane output to the pane height and a TUI dialog is drawn with blank
  # separator rows, so blank lines carry no signal here — dropping them is what makes
  # "the last line" mean the last thing the CLI actually rendered.
  def self.current_screen(text)
    text.to_s.lines.map(&:rstrip).reject(&:empty?).last(TAIL_LINES)
  end
  private_class_method :current_screen

  def self.truncate(message)
    return message if message.length <= MAX_MESSAGE_LENGTH

    "#{message[0, MAX_MESSAGE_LENGTH]}…"
  end
  private_class_method :truncate
end
