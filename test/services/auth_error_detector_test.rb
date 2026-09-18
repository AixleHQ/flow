# frozen_string_literal: true

require "test_helper"

class AuthErrorDetectorTest < ActiveSupport::TestCase
  test "returns false for blank text" do
    assert_not AuthErrorDetector.detect(nil).auth_error?
    assert_not AuthErrorDetector.detect("").auth_error?
  end

  test "returns false for unrelated output" do
    assert_not AuthErrorDetector.detect("Running tests… 42 assertions, 0 failures").auth_error?
  end

  test "does not fire on ordinary mentions of login" do
    text = "I added a login form to app/frontend/pages/Login.tsx and wired the login route."
    assert_not AuthErrorDetector.detect(text).auth_error?
  end

  test "detects the Claude Code expired-login banner" do
    result = AuthErrorDetector.detect("Login expired · Please run /login")
    assert result.auth_error?
    assert_equal "Login expired · Please run /login", result.message
  end

  test "detects an invalid Claude API key" do
    assert AuthErrorDetector.detect("Invalid API key · Please run /login").auth_error?
  end

  test "detects a CLI instructing a fresh login" do
    assert AuthErrorDetector.detect("Not authenticated. Please run `codex login` to continue.").auth_error?
    assert AuthErrorDetector.detect("run cursor-agent login").auth_error?
  end

  test "detects an OAuth-level rejection" do
    assert AuthErrorDetector.detect("token refresh failed: invalid_grant").auth_error?
    assert AuthErrorDetector.detect("OAuth token has expired").auth_error?
  end

  test "detects a dead Gemini API key" do
    assert AuthErrorDetector.detect("API key not valid. Please pass a valid API key.").auth_error?
  end

  test "match is case insensitive" do
    assert AuthErrorDetector.detect("LOGIN EXPIRED").auth_error?
  end

  test "reports the matching line out of a full pane dump" do
    pane = <<~PANE
      $ claude
      Welcome back
      Login expired · Please run /login
      >
    PANE

    assert_equal "Login expired · Please run /login", AuthErrorDetector.detect(pane).message
  end

  test "truncates a very long matching line" do
    result = AuthErrorDetector.detect("Login expired #{'x' * 600}")
    assert_equal AuthErrorDetector::MAX_MESSAGE_LENGTH + 1, result.message.length
    assert result.message.end_with?("…")
  end
end
