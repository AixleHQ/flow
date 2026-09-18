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

    test "fetches agent models from the authenticated Antigravity catalogue in API order" do
      stub = stub_request(:post, Antigravity::Api::MODELS_URL)
             .with(
               headers: { "Authorization" => "Bearer tok-123", "Content-Type" => "application/json" },
               body: { project: Antigravity::Api::CONSUMER_PROJECT }.to_json
             )
             .to_return(
               status: 200,
               body: {
                 models: {
                   "gemini-pro-agent" => { displayName: "Gemini Pro" },
                   "claude-sonnet-4-6" => { displayName: "Claude Sonnet 4.6" },
                   "image-model" => { displayName: "Image model" }
                 },
                 agentModelSorts: [ { groups: [ { modelIds: %w[claude-sonnet-4-6 gemini-pro-agent missing-model] } ] } ]
               }.to_json
             )

      result = @adapter.fetch_available_models_with_source({ "access_token" => "tok-123" })

      assert_requested stub
      assert_equal :api, result[:source]
      assert_equal %w[claude-sonnet-4-6 gemini-pro-agent], result[:models].pluck(:model_id)
      assert_equal [ "Claude Sonnet 4.6", "Gemini Pro" ], result[:models].pluck(:display_name)
    end

    test "decodes a gzip-compressed Antigravity catalogue" do
      payload = { models: { "gemini-pro-agent" => { displayName: "Gemini Pro" } },
                  agentModelSorts: [ { groups: [ { modelIds: [ "gemini-pro-agent" ] } ] } ] }.to_json
      compressed = StringIO.new
      Zlib::GzipWriter.wrap(compressed) { |gzip| gzip.write(payload) }
      stub_request(:post, Antigravity::Api::MODELS_URL)
        .to_return(status: 200, body: compressed.string, headers: { "Content-Encoding" => "gzip" })

      result = @adapter.fetch_available_models_with_source({ "access_token" => "tok-123" })

      assert_equal :api, result[:source]
      assert_equal [ "gemini-pro-agent" ], result[:models].pluck(:model_id)
    end

    test "offers the fallback Antigravity model catalogue without an access token" do
      result = @adapter.fetch_available_models_with_source({})

      assert_equal :fallback, result[:source]
      assert_includes result[:models],
                      { model_id: "gemini-3.8-flash-medium", display_name: "Gemini 3.8 Flash (Medium)" }
      assert_includes result[:models],
                      { model_id: "claude-sonnet-4-6", display_name: "Claude Sonnet 4.6 (Thinking)" }
      assert_includes result[:models],
                      { model_id: "gpt-oss-120b-medium", display_name: "GPT-OSS 120B (Medium)" }
    end

    test "fallback catalogue offers the supported replacement, not the deprecated Gemini 3.1 Pro id" do
      result = @adapter.fetch_available_models_with_source({})

      model_ids = result[:models].pluck(:model_id)
      assert_includes model_ids, "gemini-pro-agent"
      refute_includes model_ids, "gemini-3.1-pro-high"
    end

    test "falls back when the Antigravity catalogue request fails" do
      stub_request(:post, Antigravity::Api::MODELS_URL).to_return(status: 401)

      result = @adapter.fetch_available_models_with_source({ "access_token" => "expired" })

      assert_equal :fallback, result[:source]
      assert_equal AntigravityCliAdapter::FALLBACK_MODELS, result[:models]
    end

    test "omits the model flag when none is selected so Antigravity uses its default" do
      assert_equal "agy --dangerously-skip-permissions --print --output-format stream-json",
                   @adapter.session_command(mode: "non_interactive", model: nil)
    end

    test "generates Antigravity MCP schema" do
      server = stub(name: "Remote API", transport: "http", url: "https://example.test/mcp", headers: { "X-Key" => "x" })
      config = JSON.parse(@adapter.mcp_config([ server ]).values.first)
      entry = config.dig("mcpServers", MCPServer.config_key_for(server.name))
      assert_equal "https://example.test/mcp", entry["serverUrl"]
      assert_equal({ "X-Key" => "x" }, entry["headers"])
    end

    test "default_env_vars hides the CLI logo and points the proxy log at Google's hosts" do
      env = @adapter.default_env_vars(@session)

      assert_equal "1", env["AGY_CLI_HIDE_LOGO"]
      assert_equal "/var/log/mitm/http.log", env["MITM_LOG_PATH"]
      assert_equal "googleapis.com,google.com", env["MITM_TRACKED_DOMAINS"]
      # Still no credential in the environment: the token travels in the config file.
      assert_nil env.values.find { |v| v.to_s.include?("access_token") }
    end

    # 51 production sessions in the 30 days to 2026-09-17 produced zero HTTP records,
    # because the proxy wrote the log and nothing ever collected it — which is why the
    # runtime's refresh protocol is still something read out of the binary rather than
    # observed.
    test "session_log_paths collects the proxy log" do
      assert_includes @adapter.session_log_paths, "/var/log/mitm/http.log"
    end

    test "credential_preflight accepts a valid OAuth token" do
      runtime, container = preflight_runtime(
        { "token" => { "access_token" => "tok-123" }, "auth_method" => "consumer" }.to_json
      )

      result = @adapter.credential_preflight(runtime, container, "abc123")

      assert result[:valid]
      assert_nil result[:error_code]
    end

    test "credential_preflight rejects a migrated API-key credential" do
      runtime, container = preflight_runtime({ "token" => { "api_key" => "legacy-key" } }.to_json)

      result = @adapter.credential_preflight(runtime, container, "abc123")

      refute result[:valid]
      assert_equal "oauth_token_missing", result[:error_code]
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
