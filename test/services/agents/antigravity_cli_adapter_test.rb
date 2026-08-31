# frozen_string_literal: true

require "test_helper"

module Agents
  class AntigravityCliAdapterTest < ActiveSupport::TestCase
    setup { @adapter = AntigravityCliAdapter.new }

    test "uses a portable API-key credential" do
      assert_equal "/home/antigravity/.gemini/antigravity-cli/aixle-api-key.json", @adapter.config_path
      assert @adapter.auth_complete?('{"api_key":"key-123"}')
      refute @adapter.auth_complete?('{}')
      assert_equal({ "api_key" => "key-123" }, @adapter.extract_credentials('{"api_key":"key-123"}'))
    end

    test "writes provider settings and credentials" do
      files = @adapter.config_files("api_key" => "key-123")
      settings = JSON.parse(files["/home/antigravity/.gemini/antigravity-cli/settings.json"])
      assert_equal "gemini", settings["modelProvider"]
      assert_equal false, settings["enableTelemetry"]
      assert_equal({ "api_key" => "key-123" }, JSON.parse(files[@adapter.config_path]))
    end

    test "uses print mode only for automatic sessions" do
      assert_equal "agy --dangerously-skip-permissions", @adapter.session_command(mode: "interactive")
      assert_equal "agy --model gemini-3.5-pro --dangerously-skip-permissions --print --output-format stream-json",
                   @adapter.session_command(mode: "non_interactive", model: "gemini-3.5-pro")
    end

    test "generates Antigravity MCP schema" do
      server = stub(name: "Remote API", transport: "http", url: "https://example.test/mcp", headers: { "X-Key" => "x" })
      config = JSON.parse(@adapter.mcp_config([ server ]).values.first)
      entry = config.dig("mcpServers", MCPServer.config_key_for(server.name))
      assert_equal "https://example.test/mcp", entry["serverUrl"]
      assert_equal({ "X-Key" => "x" }, entry["headers"])
    end
  end
end
