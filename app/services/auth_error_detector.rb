# frozen_string_literal: true

# Recognises an agent CLI reporting that its login is no longer usable.
#
# A dead credential is not an error the container can report: the CLI prints a banner,
# renders its prompt and waits for a human who is not there. The session then produces no
# further output and is reaped by the no-output watchdog 30 minutes later — as "no output",
# which says nothing about why. Of 355 such sessions in the 14 days to 2026-09-17, 138 (41%)
# carried one of these banners.
#
# So this is the counterpart of QuotaErrorDetector: same shape, same call sites, different
# cause. Both read the terminal log, because the terminal is the only place the CLI says it.
#
# The patterns are deliberately narrow — an auth verdict fails a workflow step and condemns a
# credential, so a false positive is expensive. `claude` and `gemini` lines are copied from
# production terminal logs; the rest are the shapes every CLI shares (an OAuth error code, a
# "run <cli> login" instruction), not invented vendor prose.
class AuthErrorDetector
  MAX_MESSAGE_LENGTH = 500

  PATTERNS = [
    # Claude Code, observed verbatim in production logs.
    /Login expired/i,
    /Please run \/login/i,
    /Invalid API key · Please run \/login/i,
    # Any CLI telling the user to log in again. The CLI name is bounded so a prompt that
    # merely mentions a login (an agent reading auth code, say) does not match.
    /run ['"`]?(?:claude|codex|cursor-agent|cursor|gemini|grok|kiro|kiro-cli|agy) (?:auth )?login/i,
    # OAuth-level rejections, printed by the CLI when a refresh or an API call is refused.
    /invalid_grant/i,
    /OAuth token (?:has )?expired/i,
    /\brefresh token (?:is )?(?:invalid|expired|revoked)/i,
    # Google's own wording for a dead API key (gemini_cli), observed in production.
    /API key not valid\. Please pass a valid API key/i,
    /\bAPI key expired\b/i
  ].freeze

  Result = Struct.new(:auth_error, :message, keyword_init: true) do
    def auth_error? = auth_error
  end

  def self.detect(text)
    return Result.new(auth_error: false) if text.blank?
    return Result.new(auth_error: false) unless PATTERNS.any? { |pat| text.match?(pat) }

    Result.new(auth_error: true, message: extract_message(text))
  end

  def self.extract_message(text)
    lines = text.to_s.lines.map(&:strip).reject(&:empty?)
    matching_line = lines.find { |line| PATTERNS.any? { |pat| line.match?(pat) } }
    return truncate(matching_line) if matching_line

    PATTERNS.each do |pat|
      match = text.match(pat)
      return truncate(match[0]) if match
    end

    truncate(text)
  end

  def self.truncate(message)
    return message if message.length <= MAX_MESSAGE_LENGTH

    "#{message[0, MAX_MESSAGE_LENGTH]}…"
  end
  private_class_method :truncate
end
