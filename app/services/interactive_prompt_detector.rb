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
# Detection is deliberately conservative: every marker of a signature has to be
# present before a session is failed. The prompt text also appears in bug reports,
# task descriptions and docs an agent may legitimately print to its own terminal,
# and a single-phrase match would kill exactly the session investigating it. The
# full set of markers only co-occurs on the rendered dialog itself.
#
# Sibling of QuotaErrorDetector — same shape, same caller
# (Activities::Workflow::ScanQuotaErrorsActivity), different blocker.
class InteractivePromptDetector
  MAX_MESSAGE_LENGTH = 500

  # Each signature: which agents can produce it, the markers that must ALL appear,
  # and the diagnostic that goes on the failed session. The message names the prompt
  # and the platform-side setting that is supposed to prevent it, so the operator
  # reading a failed step does not have to rediscover the cause.
  SIGNATURES = [
    {
      id: :codex_workspace_trust,
      agent_types: %w[codex],
      markers: [
        /Do you trust the contents of this directory\?/i,
        /Yes,\s*continue/i,
        /No,\s*quit/i
      ],
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

    SIGNATURES.each do |signature|
      next if agent_type.present? && signature[:agent_types].exclude?(agent_type.to_s)
      next unless signature[:markers].all? { |marker| text.match?(marker) }

      return Result.new(
        blocked: true,
        prompt_id: signature[:id],
        message: truncate("Session terminated: #{signature[:message]}")
      )
    end

    Result.new(blocked: false)
  end

  def self.truncate(message)
    return message if message.length <= MAX_MESSAGE_LENGTH

    "#{message[0, MAX_MESSAGE_LENGTH]}…"
  end
  private_class_method :truncate
end
