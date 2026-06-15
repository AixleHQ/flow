# frozen_string_literal: true

require "test_helper"

class QuotaErrorDetectorTest < ActiveSupport::TestCase
  # --- quota_error? predicate ---

  test "returns false for blank text" do
    result = QuotaErrorDetector.detect(nil)
    assert_not result.quota_error?
  end

  test "returns false for empty string" do
    result = QuotaErrorDetector.detect("")
    assert_not result.quota_error?
  end

  test "returns false for unrelated error text" do
    result = QuotaErrorDetector.detect("Connection timeout: could not reach server")
    assert_not result.quota_error?
  end

  # --- Anthropic patterns ---

  test "detects anthropic credit balance error (with 'is')" do
    result = QuotaErrorDetector.detect("Error: Your credit balance is too low to complete this request")
    assert result.quota_error?
    assert_equal :anthropic, result.provider
  end

  test "detects anthropic credit balance error (without 'is', real CLI format)" do
    result = QuotaErrorDetector.detect("Credit balance too low · Add funds: https://platform.claude.com/settings/billing")
    assert result.quota_error?
    assert_equal :anthropic, result.provider
  end

  test "detects anthropic add funds URL" do
    result = QuotaErrorDetector.detect("Add funds: https://platform.claude.com/settings/billing")
    assert result.quota_error?
    assert_equal :anthropic, result.provider
  end

  test "detects anthropic insufficient_quota" do
    result = QuotaErrorDetector.detect("API error: insufficient_quota")
    assert result.quota_error?
    assert_equal :anthropic, result.provider
  end

  test "detects anthropic billing_hard_limit" do
    result = QuotaErrorDetector.detect("Request blocked: billing_hard_limit reached")
    assert result.quota_error?
    assert_equal :anthropic, result.provider
  end

  test "anthropic match is case insensitive" do
    result = QuotaErrorDetector.detect("YOUR CREDIT BALANCE IS TOO LOW")
    assert result.quota_error?
    assert_equal :anthropic, result.provider
  end

  # --- OpenAI patterns ---

  test "detects openai quota exceeded" do
    result = QuotaErrorDetector.detect("You exceeded your current quota, please check your plan and billing details")
    assert result.quota_error?
    assert_equal :openai, result.provider
  end

  test "detects openai codex quota exceeded message" do
    text = <<~TEXT
      codex --yolo
      Quota exceeded. Check your plan and billing details.
      codex@abc123:/workspace$
    TEXT

    result = QuotaErrorDetector.detect(text)

    assert result.quota_error?
    assert_equal :openai, result.provider
    assert_equal "Quota exceeded. Check your plan and billing details.", result.message
  end

  test "detects openai insufficient_credits" do
    result = QuotaErrorDetector.detect("Error: insufficient_credits — add more credits to continue")
    assert result.quota_error?
    assert_equal :openai, result.provider
  end

  test "detects openai quota_exceeded keyword" do
    result = QuotaErrorDetector.detect("error_code: quota_exceeded")
    assert result.quota_error?
    assert_equal :openai, result.provider
  end

  # --- Gemini patterns ---

  test "detects gemini RESOURCE_EXHAUSTED status" do
    result = QuotaErrorDetector.detect('{"status":"RESOURCE_EXHAUSTED","message":"Too many requests"}')
    assert result.quota_error?
    assert_equal :gemini, result.provider
  end

  test "detects gemini resource exhausted message" do
    result = QuotaErrorDetector.detect("Resource has been exhausted (e.g. check quota).")
    assert result.quota_error?
    assert_equal :gemini, result.provider
  end

  test "detects gemini generativelanguage quota metric" do
    text = "Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 20"
    result = QuotaErrorDetector.detect(text)
    assert result.quota_error?
    assert_equal :gemini, result.provider
    assert_equal text, result.message
  end

  test "detects gemini quota message with generativelanguage hint" do
    text = "You exceeded your current quota, please check your plan and billing details. Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_requests"
    result = QuotaErrorDetector.detect(text)
    assert result.quota_error?
    assert_equal :gemini, result.provider
  end

  test "detects gemini cli 429 API error format" do
    text = '[API Error: got status: 429 Too Many Requests. {"error":{"message":"Resource has been exhausted"}}]'
    result = QuotaErrorDetector.detect(text)
    assert result.quota_error?
    assert_equal :gemini, result.provider
  end

  test "detects gemini cli usage limit reached for pro models" do
    text = <<~TEXT
      gemini --model gemini-3.1-pro-preview --yolo
      Usage limit reached for all Pro models.
      /stats model for usage details
      /model to switch models.
    TEXT

    result = QuotaErrorDetector.detect(text)

    assert result.quota_error?
    assert_equal :gemini, result.provider
    assert_equal "Usage limit reached for all Pro models.", result.message
  end

  test "detects gemini cli AI Studio quota increase hint" do
    text = "Please wait and try again later. To increase your limits, request a quota increase through AI Studio, or switch to another /auth method"
    result = QuotaErrorDetector.detect(text)
    assert result.quota_error?
    assert_equal :gemini, result.provider
    assert_equal text, result.message
  end

  test "extracts gemini quota line from terminal capture" do
    text = <<~TEXT
      gemini --yolo
      ✕ [API Error: got status: 429 Too Many Requests. {"error":{"message":"Resource has been exhausted (e.g. check quota)."}}]
      gemini@abc123:/workspace$
    TEXT

    result = QuotaErrorDetector.detect(text)

    assert result.quota_error?
    assert_equal :gemini, result.provider
    assert_includes result.message, "429 Too Many Requests"
  end

  # --- Cursor patterns ---

  test "detects cursor normal usage limit message" do
    result = QuotaErrorDetector.detect("Error: You've reached your normal usage limit.")
    assert result.quota_error?
    assert_equal :cursor, result.provider
    assert_equal "Error: You've reached your normal usage limit.", result.message
  end

  test "detects cursor out of usage admin message" do
    text = "You're out of usage. Ask your admin to increase your limit to continue."
    result = QuotaErrorDetector.detect(text)
    assert result.quota_error?
    assert_equal :cursor, result.provider
    assert_equal text, result.message
  end

  test "extracts cursor usage limit line from terminal capture" do
    text = <<~TEXT
      agent --force
      Error: You've reached your normal usage limit.
      You're out of usage. Ask your admin to increase your limit to continue.
    TEXT

    result = QuotaErrorDetector.detect(text)

    assert result.quota_error?
    assert_equal :cursor, result.provider
    assert_equal "Error: You've reached your normal usage limit.", result.message
  end

  # --- Result fields ---

  test "result message is the matching line, not the full input" do
    message = "API error: insufficient_quota for this user"
    result = QuotaErrorDetector.detect(message)
    assert_equal message, result.message
  end

  test "extracts matching line from large terminal capture" do
    text = <<~TEXT
      claude@abc123:/workspace$
      claude "$AGENT_PROMPT"
      Credit balance too low · Add funds: https://platform.claude.com/settings/billing
      claude@abc123:/workspace$
    TEXT

    result = QuotaErrorDetector.detect(text)

    assert result.quota_error?
    assert_equal "Credit balance too low · Add funds: https://platform.claude.com/settings/billing",
                 result.message
  end

  test "non-matching result has nil provider and nil message" do
    result = QuotaErrorDetector.detect("some random error")
    assert_not result.quota_error?
    assert_nil result.provider
    assert_nil result.message
  end
end
