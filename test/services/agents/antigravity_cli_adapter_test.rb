# frozen_string_literal: true

require "test_helper"

module Agents
  class AntigravityCliAdapterTest < ActiveSupport::TestCase
    setup { @adapter = AntigravityCliAdapter.new }

    test "uses a portable API-key credential" do
      assert_equal "/home/antigravity/.gemini/antigravity-cli/aixle-api-key.json", @adapter.config_path
      assert @adapter.auth_complete?('{"api_key":"key-123"}')
      refute @adapter.auth_complete?("{}")
      assert_equal({ "api_key" => "key-123" }, @adapter.extract_credentials('{"api_key":"key-123"}'))
    end

    test "writes provider settings and credentials" do
      files = @adapter.config_files("api_key" => "key-123")
      settings = JSON.parse(files["/home/antigravity/.gemini/antigravity-cli/settings.json"])
      assert_equal "gemini", settings["modelProvider"]
      refute settings["enableTelemetry"]
      assert_equal({ "api_key" => "key-123" }, JSON.parse(files[@adapter.config_path]))
    end

    test "keeps credential file creation in the backend adapter" do
      files = @adapter.auth_setup_files
      assert_equal({ "modelProvider" => "gemini", "enableTelemetry" => false, "showTips" => false },
                   JSON.parse(files["/home/antigravity/.gemini/antigravity-cli/settings.json"]))
      assert_equal "key-123", JSON.parse(@adapter.config_files("api_key" => "key-123")[@adapter.config_path])["api_key"]
    end

    # `agy`'s only headless-safe auth mode reads GEMINI_API_KEY from the environment
    # at startup and has no interactive credential prompt of its own (confirmed
    # against the real CLI — it exits immediately if that var is unset). So the auth
    # terminal drives a login script instead of the CLI directly: the user is
    # prompted for a key, `agy` validates it live, and only a verified key is written
    # to #config_path — the same file every other auth check here already assumes.
    test "seeds a login script that validates the key with the real CLI before writing it" do
      files = @adapter.auth_setup_files
      script = files["/home/antigravity/.aixle/antigravity-login.sh"]

      assert script.present?
      assert_includes script, "read -r key"
      assert_includes script, "GEMINI_API_KEY=\"$key\" agy --print"
      assert_includes script, "$HOME/.gemini/antigravity-cli/aixle-api-key.json"
      # A rejected/empty key must never reach the credential file the watcher polls.
      assert_match(/exit 1/, script)
    end

    test "drives the auth terminal through the login script, not the bare CLI" do
      assert_equal [ "sh /home/antigravity/.aixle/antigravity-login.sh" ], @adapter.auth_launch_commands_for("agent")
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
