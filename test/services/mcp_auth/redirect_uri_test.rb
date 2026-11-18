# frozen_string_literal: true

require "test_helper"

class MCPAuth::RedirectUriTest < ActiveSupport::TestCase
  test "a client may register https anywhere, http on loopback only, and a native app's own scheme" do
    assert MCPAuth::RedirectUri.registrable?("https://claude.ai/api/mcp/auth_callback")
    assert MCPAuth::RedirectUri.registrable?("http://127.0.0.1:33418/callback")
    assert MCPAuth::RedirectUri.registrable?("http://localhost/callback")
    assert MCPAuth::RedirectUri.registrable?("cursor://anysphere.cursor-retrieval/oauth/callback")
    assert MCPAuth::RedirectUri.registrable?("com.example.app:/oauth")

    assert_not MCPAuth::RedirectUri.registrable?("http://evil.example/callback")
    assert_not MCPAuth::RedirectUri.registrable?("javascript:alert(1)")
    assert_not MCPAuth::RedirectUri.registrable?("data:text/html,hi")
    assert_not MCPAuth::RedirectUri.registrable?("https://claude.ai/cb#fragment")
    assert_not MCPAuth::RedirectUri.registrable?("https://user:pw@claude.ai/cb")
    assert_not MCPAuth::RedirectUri.registrable?("/relative")
    assert_not MCPAuth::RedirectUri.registrable?(nil)
  end

  # Claude Code's metadata document lists http://localhost/callback and then
  # signs in on an ephemeral port (RFC 8252 §7.3).
  test "a loopback URI matches on any port, everything else exactly" do
    registered = %w[http://localhost/callback http://127.0.0.1/callback https://claude.ai/api/mcp/auth_callback]

    assert MCPAuth::RedirectUri.allowed?(registered, "http://localhost:3118/callback")
    assert MCPAuth::RedirectUri.allowed?(registered, "http://127.0.0.1:51000/callback")
    assert MCPAuth::RedirectUri.allowed?(registered, "https://claude.ai/api/mcp/auth_callback")

    assert_not MCPAuth::RedirectUri.allowed?(registered, "http://localhost:3118/other")
    assert_not MCPAuth::RedirectUri.allowed?(registered, "http://127.0.0.1.evil.example:80/callback")
    assert_not MCPAuth::RedirectUri.allowed?(registered, "https://claude.ai:8443/api/mcp/auth_callback")
    assert_not MCPAuth::RedirectUri.allowed?(registered, "https://claude.ai/api/mcp/auth_callback?x=1")
    assert_not MCPAuth::RedirectUri.allowed?(registered, nil)
  end

  test "the answer keeps the redirect URI's own query" do
    url = MCPAuth::RedirectUri.with_params("https://app.example/cb?tenant=a", code: "c1", state: nil)

    assert_equal "https://app.example/cb?tenant=a&code=c1", url
  end

  test "the consent screen names where the browser goes" do
    assert_equal "claude.ai", MCPAuth::RedirectUri.destination("https://claude.ai/api/mcp/auth_callback")
    assert_equal "an app on this computer (localhost)", MCPAuth::RedirectUri.destination("http://localhost:1/cb")
    assert_equal "an app on this computer (cursor:)", MCPAuth::RedirectUri.destination("cursor://x/cb")
    assert MCPAuth::RedirectUri.on_this_computer?("http://localhost:1/cb")
    assert_not MCPAuth::RedirectUri.on_this_computer?("https://claude.ai/cb")
  end
end
