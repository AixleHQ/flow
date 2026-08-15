# frozen_string_literal: true

# InteractivePromptDetector
#
# Finds CLI startup prompts in live terminal output that a `non_interactive`
# session can never answer. Such a session does not fail and does not finish: the
# CLI sits on a TTY dialog, the terminal produces no further bytes, the step stays
# `running` and the terminal session stays `ready` on zero tokens until a human
# notices (task #605 — Codex's workspace-trust dialog wedged run 3190 / step run
# 3476 / session 3834 for ~52 minutes).
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
      id: :codex_workspace_trust,
      agent_types: %w[codex],
      markers: [
        /Do you trust the contents of this directory\?/i,
        /Yes,\s*continue/i,
        /No,\s*quit/i
      ],
      # The last thing a blocked pane shows: the "press enter" hint, or — when the
      # pane is captured before that line renders — the final option of the dialog.
      # Anchored past the TUI's selection decoration ("› 1. ", "  2. ") so prose that
      # merely mentions the phrase mid-sentence does not qualify as a footer.
      footer: /\A[\s>›*•|-]*(?:\d+[.)]\s*)?(?:No,\s*quit|Press enter to continue)\b/i,
      message: "Codex is blocked on the workspace-trust prompt " \
               '("Do you trust the contents of this directory?"), which a non_interactive ' \
               "session cannot answer. Trust is granted both on the launch command " \
               "(Agents::CodexAdapter#cli_trust_flag) and by the [projects.\"<workspace>\"] " \
               "entry in ~/.codex/config.toml — both were missing for this container."
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
