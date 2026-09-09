# frozen_string_literal: true

require "test_helper"

# The browser renders the whole `connections` list, but a workflow-step launch
# has no browser: this message is the only account of the refusal that reaches
# the admission, the session and whoever is reading the run.
class Oauth::PreflightErrorTest < ActiveSupport::TestCase
  test "the message names the server that needs connecting" do
    error = Oauth::PreflightError.new([ { mcp_server_id: 51, name: "Sentry", connect_url: "/oauth/mcp/51/connect" } ])

    assert_equal "Connect required before launching: Sentry", error.message
  end

  test "several servers are all named" do
    error = Oauth::PreflightError.new([
      { mcp_server_id: 51, name: "Sentry" }, { mcp_server_id: 48, name: "Railway MCP" }
    ])

    assert_equal "Connect required before launching: Sentry, Railway MCP", error.message
  end

  test "a server with no name falls back to something an operator can look up" do
    error = Oauth::PreflightError.new([ { mcp_server_id: 51 } ])

    assert_equal "Connect required before launching: MCP server #51", error.message
  end
end
