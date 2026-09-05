# frozen_string_literal: true

require "test_helper"

module Agents
  class AntigravityCliAdapterTest < ActiveSupport::TestCase
    setup do
      @adapter = AntigravityCliAdapter.new
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @session = create(:terminal_session, :running, user: @user, project: @project)
    end

    test "uses the OAuth token file agy itself writes on login" do
      assert_equal "/home/antigravity/.gemini/antigravity-cli/antigravity-oauth-token", @adapter.config_path
      assert_equal @adapter.config_path, @adapter.auth_watch_path
      assert @adapter.auth_complete?('{"token":{"access_token":"tok-123"},"auth_method":"consumer"}')
      refute @adapter.auth_complete?('{"auth_method":"consumer"}')
      refute @adapter.auth_complete?("{}")
      assert_equal(
        { "access_token" => "tok-123", "refresh_token" => "refresh-123", "auth_method" => "consumer" },
        @adapter.extract_credentials(
          '{"token":{"access_token":"tok-123","refresh_token":"refresh-123","other":"ignored"},"auth_method":"consumer"}'
        )
      )
    end

    test "extract_credentials returns nothing for a file with no token block yet" do
      assert_equal({}, @adapter.extract_credentials('{"enableTelemetry":false,"trustedWorkspaces":["/workspace"]}'))
    end

    test "writes OAuth settings and credentials in the exact shape agy itself writes" do
      credentials = { "access_token" => "tok-123", "refresh_token" => "refresh-123", "auth_method" => "consumer" }
      files = @adapter.config_files(credentials)
      settings = JSON.parse(files["/home/antigravity/.gemini/antigravity-cli/settings.json"])
      assert_not_includes settings, "modelProvider"
      refute settings["enableTelemetry"]
      assert_equal(
        { "token" => { "access_token" => "tok-123", "refresh_token" => "refresh-123" }, "auth_method" => "consumer" },
        JSON.parse(files[@adapter.config_path])
      )
    end

    # Per review feedback, the auth terminal drives the real `agy` CLI directly
    # (its own interactive login, confirmed offering Google OAuth or a Google
    # Cloud project — both a real human completes themselves) rather than a
    # backend-written script; only the pre-login settings file is seeded upfront.
    test "seeds only OAuth-compatible settings before login, no bespoke script" do
      files = @adapter.auth_setup_files
      assert_equal({ "enableTelemetry" => false, "showTips" => false },
                   JSON.parse(files["/home/antigravity/.gemini/antigravity-cli/settings.json"]))
      assert_equal [ "/home/antigravity/.gemini/antigravity-cli/settings.json" ], files.keys
    end

    test "drives the auth terminal through the bare CLI, same as every other adapter" do
      assert_equal [], @adapter.auth_launch_commands_for("agent")
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

    test "default_env_vars only hides the CLI logo, no credential is passed via env" do
      assert_equal({ "AGY_CLI_HIDE_LOGO" => "1" }, @adapter.default_env_vars(@session))
    end

    test "credential_preflight accepts a valid OAuth token" do
      runtime, container = preflight_runtime(
        { "token" => { "access_token" => "tok-123" }, "auth_method" => "consumer" }.to_json
      )

      assert_equal({ valid: true, error_code: nil }, @adapter.credential_preflight(runtime, container, "abc123"))
    end

    test "credential_preflight rejects a migrated API-key credential" do
      runtime, container = preflight_runtime({ "token" => { "api_key" => "legacy-key" } }.to_json)

      assert_equal({ valid: false, error_code: "oauth_token_missing" },
                   @adapter.credential_preflight(runtime, container, "abc123"))
    end

    test "credential_preflight rejects a missing token file" do
      runtime, container = preflight_runtime(nil)

      assert_equal({ valid: false, error_code: "auth_file_missing" },
                   @adapter.credential_preflight(runtime, container, "abc123"))
    end

    private

    def preflight_runtime(auth_content)
      filesystem = {}
      filesystem[@adapter.config_path] = auth_content unless auth_content.nil?
      runtime = ContainerRuntime::FakeRuntime.new(agent_type: "antigravity_cli", filesystem: filesystem)
      [ runtime, runtime.resolve_container("abc123") ]
    end
  end
end
