# frozen_string_literal: true

# QuotaErrorDetector
#
# Recognises an agent CLI that has stopped on its provider's quota or credit error.
#
# Two kinds of caller hand it text:
#
#   - .detect reads a session's stored error message. Every caller passes the
#     session's agent_type, so only its own provider counts.
#   - .detect_on_screen reads terminal output: a live pane (ScanQuotaErrorsActivity,
#     Sessions::LogTail) or a finished session's stored log (CompleteStepActivity,
#     Sessions::LogTail). That text is mostly the agent's own work, and an agent greps,
#     reads, edits and tests code that names these errors: this class, its tests, the
#     run failure reasons. Task #195: a Kiro session was failed within a minute of
#     grepping a line of ShowPage.tsx that held one of OpenAI's identifiers, and runs
#     that survived the scan were still failed at step completion by the same text in
#     their stored log. So terminal output is read only for the session's own
#     provider, and only on its trailing block, where a CLI renders the error it
#     stopped on. Whether a live pane has also gone quiet is the caller's to check
#     (QUIET_BEFORE_FAIL), because only the caller can read the pane's last output
#     time.
class QuotaErrorDetector
  MAX_MESSAGE_LENGTH = 500

  # How much of a live pane counts as "the current screen", as in
  # InteractivePromptDetector and Sessions::AuthPause: a CLI's error plus the prompt
  # box or status line drawn under it, never the 1,000 lines of scrollback.
  TAIL_LINES = 40

  # A CLI that stopped on a quota error prints nothing more, and a working agent
  # does. A live pane has to have been silent this long before its screen counts.
  QUIET_BEFORE_FAIL = 1.minute

  PATTERNS = {
    anthropic: [
      /credit balance(?:\s+is)?\s+too low/i,
      /insufficient_quota/i,
      /billing_hard_limit/i,
      /Add funds:.*platform\.claude\.com/i,
      /individual spend limit/i,
      /workspace API usage limits/i,
      /You will regain access on/i
    ],
    gemini: [
      /Usage limit reached/i,
      /RESOURCE_EXHAUSTED/i,
      /Resource has been exhausted.*check quota/i,
      /Quota exceeded for metric:.*generativelanguage/i,
      /You exceeded your current quota.*generativelanguage/i,
      /\[API Error: got status: 429/i,
      /request a quota increase through AI Studio/i,
      # Antigravity CLI (Google AI credits), read from the 1.3.1 binary. Not caught by
      # anthropic's "credit balance" pattern: Google writes "credits balance".
      /AI credits balance is too low/i
    ],
    openai: [
      /You exceeded your current quota/i,
      /insufficient_credits/i,
      /quota_exceeded/i,
      /Quota exceeded. Check your plan and billing details/i
    ],
    cursor: [
      /reached your normal usage limit/i,
      /you'?re out of usage/i,
      /increase your limit to continue/i,
      /usage limit has been reached/i
    ],
    # Grok CLI's own rendered limit messages, plus the phrases it classifies a
    # quota/billing rejection by ("out of credits", "usage balance exhausted").
    xai: [
      /out of credits/i,
      /usage balance exhausted/i,
      /Add credits and retry/i,
      /You'?ve hit the rate limit for your plan/i,
      /You hit your (?:weekly|free usage) limit/i,
      /Purchase credits to keep using Grok/i
    ],
    # Kiro meters in credits, and its CLI exits 1 for every failure — a bad flag and an
    # exhausted plan are the same exit code — so the rendered message is the only thing
    # that tells a quota stop apart from a crash.
    kiro: [
      /reached your monthly usage limit/i,
      /reached your overage limit/i,
      /Kiro rate limit reached/i,
      /Request quota exceeded/i
    ]
  }.freeze

  # The provider whose errors each agent CLI renders (AgentCredentialsService::ADAPTERS).
  # Antigravity runs on Google's models and Google's credits.
  AGENT_PROVIDERS = {
    "claude_code" => :anthropic,
    "codex" => :openai,
    "gemini_cli" => :gemini,
    "antigravity_cli" => :gemini,
    "cursor_cli" => :cursor,
    "grok" => :xai,
    "kiro_cli" => :kiro
  }.freeze

  Result = Struct.new(:quota_error, :provider, :message, keyword_init: true) do
    def quota_error? = quota_error
  end

  # @param text [String, nil]
  # @param agent_type [String, nil] the session's agent_type. When it names a known
  #   agent, only that agent's provider is matched; without one every provider is.
  # @return [Result]
  def self.detect(text, agent_type: nil)
    return Result.new(quota_error: false) if text.blank?

    patterns_for(agent_type).each do |provider, patterns|
      next unless patterns.any? { |pat| text.match?(pat) }

      return Result.new(
        quota_error: true,
        provider: provider,
        message: extract_message(text, patterns)
      )
    end

    Result.new(quota_error: false)
  end

  # Terminal output, live or stored: matched on its trailing TAIL_LINES nonblank lines
  # only, with the session's own provider's patterns.
  #
  # @param text [String, nil] terminal output: a tmux capture-pane, or an ANSI-stripped log
  # @param agent_type [String, nil] the session's agent_type
  # @return [Result]
  def self.detect_on_screen(text, agent_type:)
    detect(current_screen(text), agent_type: agent_type)
  end

  def self.patterns_for(agent_type)
    provider = AGENT_PROVIDERS[agent_type.to_s]
    provider ? PATTERNS.slice(provider) : PATTERNS
  end

  # tmux pads capture-pane output to the pane height, so blank lines carry no signal:
  # dropping them is what makes the tail the last thing the CLI actually rendered.
  def self.current_screen(text)
    text.to_s.dup.force_encoding(Encoding::UTF_8).scrub
        .lines.map(&:rstrip).reject(&:empty?).last(TAIL_LINES).join("\n")
  end

  def self.extract_message(text, patterns)
    lines = text.to_s.lines.map(&:strip).reject(&:empty?)
    matching_line = lines.find { |line| patterns.any? { |pat| line.match?(pat) } }
    return truncate(matching_line) if matching_line

    patterns.each do |pat|
      match = text.match(pat)
      return truncate(match[0]) if match
    end

    truncate(text)
  end

  def self.truncate(message)
    return message if message.length <= MAX_MESSAGE_LENGTH

    "#{message[0, MAX_MESSAGE_LENGTH]}…"
  end
  private_class_method :patterns_for, :current_screen, :truncate
end
