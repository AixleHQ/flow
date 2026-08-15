# frozen_string_literal: true

class QuotaErrorDetector
  MAX_MESSAGE_LENGTH = 500

  PATTERNS = {
    anthropic: [
      /credit balance(?:\s+is)?\s+too low/i,
      /insufficient_quota/i,
      /billing_hard_limit/i,
      /Add funds:.*platform\.claude\.com/i,
      /individual spend limit/i
    ],
    gemini: [
      /Usage limit reached/i,
      /RESOURCE_EXHAUSTED/i,
      /Resource has been exhausted.*check quota/i,
      /Quota exceeded for metric:.*generativelanguage/i,
      /You exceeded your current quota.*generativelanguage/i,
      /\[API Error: got status: 429/i,
      /request a quota increase through AI Studio/i
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
    ]
  }.freeze

  Result = Struct.new(:quota_error, :provider, :message, keyword_init: true) do
    def quota_error? = quota_error
  end

  def self.detect(text)
    return Result.new(quota_error: false) if text.blank?

    PATTERNS.each do |provider, patterns|
      next unless patterns.any? { |pat| text.match?(pat) }

      return Result.new(
        quota_error: true,
        provider: provider,
        message: extract_message(text, patterns)
      )
    end

    Result.new(quota_error: false)
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
  private_class_method :truncate
end
