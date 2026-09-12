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
      assert_equal [ "/workspace" ], settings["trustedWorkspaces"]
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
      assert_equal({ "enableTelemetry" => false, "showTips" => false, "trustedWorkspaces" => [ "/workspace" ] },
                   JSON.parse(files["/home/antigravity/.gemini/antigravity-cli/settings.json"]))
      assert_equal [ "/home/antigravity/.gemini/antigravity-cli/settings.json",
                     "/home/antigravity/.gemini/antigravity-cli/cache/onboarding.json" ], files.keys
    end

    # Every session otherwise opens on the colour-scheme picker and the data-use
    # consent screen and waits for a keypress no automatic session ever sends.
    test "answers the first-run wizard so no session opens on it" do
      [ @adapter.auth_setup_files, @adapter.config_files({ "access_token" => "tok-123" }) ].each do |files|
        onboarding = JSON.parse(files["/home/antigravity/.gemini/antigravity-cli/cache/onboarding.json"])
        assert onboarding["onboardingComplete"]
        assert onboarding["consumerOnboardingComplete"]
        refute onboarding["enterpriseOnboardingComplete"]
      end
    end

    test "drives the auth terminal through the bare CLI, same as every other adapter" do
      assert_equal [], @adapter.auth_launch_commands_for("agent")
    end

    # `agy` rejects a positional prompt ("unexpected argument"), so the trailing
    # -i is what turns the prompt AgentSessionStrategy appends into a flag value.
    test "runs the TUI in both modes and takes an automatic session prompt through -i" do
      assert_equal "agy --dangerously-skip-permissions", @adapter.session_command(mode: "interactive")
      assert_equal "agy --dangerously-skip-permissions",
                   @adapter.session_command(mode: "non_interactive", prompt: nil)
      assert_equal "agy --model gemini-3.5-pro --dangerously-skip-permissions -i",
                   @adapter.session_command(mode: "non_interactive", prompt: "ship it", model: "gemini-3.5-pro")
    end

    test "generates Antigravity MCP schema" do
      server = stub(name: "Remote API", transport: "http", url: "https://example.test/mcp", headers: { "X-Key" => "x" })
      config = JSON.parse(@adapter.mcp_config([ server ]).values.first)
      entry = config.dig("mcpServers", MCPServer.config_key_for(server.name))
      assert_equal "https://example.test/mcp", entry["serverUrl"]
      assert_equal({ "X-Key" => "x" }, entry["headers"])
    end

    test "default_env_vars carries no credential material" do
      env = @adapter.default_env_vars(@session)
      assert_equal "1", env["AGY_CLI_HIDE_LOGO"]
      assert_equal %w[AGY_CLI_HIDE_LOGO MITM_LOG_PATH MITM_TRACKED_DOMAINS], env.keys.sort
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

    # =========================================================================
    # fetch_available_models
    # =========================================================================

    # `agentModelSorts` is what the CLI itself shows; the full `models` map also
    # carries internal entries (tab completion, chat experiments) that `--model`
    # is not meant to take, so anything outside the sort order is dropped.
    test "fetch_available_models takes the CLI's own agent list, not the whole catalogue" do
      body = {
        "models" => {
          "gemini-3.8-flash-high" => { "displayName" => "Gemini 3.8 Flash (High)", "maxTokens" => 1_048_576 },
          "claude-sonnet-4-6" => { "displayName" => "Claude Sonnet 4.6 (Thinking)" },
          "tab_flash_lite_preview" => { "maxTokens" => 32_768 }
        },
        "agentModelSorts" => [
          { "groups" => [ { "modelIds" => [ "gemini-3.8-flash-high", "claude-sonnet-4-6", "not-in-catalogue" ] } ] }
        ]
      }.to_json
      stub_request(:post, AntigravityCliAdapter::MODELS_URL)
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      result = @adapter.fetch_available_models_with_source({ "access_token" => "tok-123" })

      assert_equal :api, result[:source]
      assert_equal(
        [ { model_id: "gemini-3.8-flash-high", display_name: "Gemini 3.8 Flash (High)",
            description: "1M token context" },
          { model_id: "claude-sonnet-4-6", display_name: "Claude Sonnet 4.6 (Thinking)" } ],
        result[:models]
      )
    end

    # The endpoint 403s on any User-Agent that is not one of Google's own
    # clients, so the header is part of the request, not decoration.
    test "fetch_available_models identifies itself as the Antigravity CLI" do
      stub = stub_request(:post, AntigravityCliAdapter::MODELS_URL)
        .with(headers: { "User-Agent" => AntigravityCliAdapter::MODELS_USER_AGENT,
                         "Authorization" => "Bearer tok-123" }, body: "{}")
        .to_return(status: 200, body: { "models" => {}, "agentModelSorts" => [] }.to_json)

      @adapter.fetch_available_models({ "access_token" => "tok-123" })

      assert_requested stub
    end

    # The stored access token expires in about an hour and nothing on our side
    # renews it, so a rejected call is the normal case — the picker still has to
    # come back populated.
    test "fetch_available_models falls back to the pinned list on a stale token" do
      stub_request(:post, AntigravityCliAdapter::MODELS_URL).to_return(status: 403, body: "")

      result = @adapter.fetch_available_models_with_source({ "access_token" => "expired" })

      assert_equal :fallback, result[:source]
      assert_equal AntigravityCliAdapter::FALLBACK_MODELS, result[:models]
    end

    test "fetch_available_models falls back without ever calling out when there is no token" do
      result = @adapter.fetch_available_models_with_source({ "auth_method" => "consumer" })

      assert_equal({ models: AntigravityCliAdapter::FALLBACK_MODELS, source: :fallback }, result)
    end

    test "migrates a stored default off the model id Antigravity retired" do
      assert_equal "gemini-pro-agent", @adapter.migrate_model_id("gemini-3.1-pro-high")
      assert_equal "claude-sonnet-4-6", @adapter.migrate_model_id("claude-sonnet-4-6")
    end

    # =========================================================================
    # Usage collection
    # =========================================================================

    test "tracks the model hosts and collects the proxy log the counts come from" do
      env = @adapter.default_env_vars(@session)
      assert_equal "/var/log/mitm/http.log", env["MITM_LOG_PATH"]
      assert_equal "cloudcode-pa.googleapis.com,daily-cloudcode-pa.googleapis.com,aicode.googleapis.com",
                   env["MITM_TRACKED_DOMAINS"]
      assert_includes @adapter.session_log_paths, "/var/log/mitm/http.log"
    end

    test "collect_usage records the usageMetadata counts from the proxy log" do
      log = [
        mitm_response("daily-cloudcode-pa.googleapis.com", {
          "modelVersion" => "gemini-3.8-flash-high",
          "usageMetadata" => { "promptTokenCount" => 1200, "candidatesTokenCount" => 300,
                               "thoughtsTokenCount" => 45, "cachedContentTokenCount" => 800 }
        }),
        mitm_response("play.googleapis.com", {
          "usageMetadata" => { "promptTokenCount" => 999_999, "candidatesTokenCount" => 999_999 }
        })
      ].join

      @adapter.collect_usage(@session, { "logs/http.log" => log })

      stat = @session.reload.usage_statistic
      assert_equal 1200, stat.input_tokens
      # Thinking tokens are billed as output and reported outside candidatesTokenCount.
      assert_equal 345, stat.output_tokens
      assert_equal 800, stat.cache_read_tokens
      assert_equal [ "gemini-3.8-flash-high" ], stat.models
      # Subscription quota, not metered per token — no price is invented.
      assert_equal 0, stat.cost_cents
    end

    # Google gzips every JSON response from this backend, and the proxy addon
    # stores a body it could not decompress as base64 rather than as mangled text.
    test "collect_usage reads a body the proxy had to store as base64" do
      payload = { "usageMetadata" => { "promptTokenCount" => 10, "candidatesTokenCount" => 5 } }.to_json
      log = mitm_response("cloudcode-pa.googleapis.com", nil,
                          body: Base64.strict_encode64(payload), encoding: "base64")

      @adapter.collect_usage(@session, { "logs/http.log" => log })

      assert_equal 10, @session.reload.usage_statistic.input_tokens
    end

    test "collect_usage leaves the session alone when the log holds no counts" do
      @adapter.collect_usage(@session, { "logs/http.log" => mitm_response("cloudcode-pa.googleapis.com", { "ok" => true }) })

      assert_nil @session.reload.usage_statistic
    end

    # A lookalike host must never be read as vendor traffic.
    test "collect_usage ignores a host that merely ends with the tracked name" do
      log = mitm_response("evil-cloudcode-pa.googleapis.com.attacker.test", {
        "usageMetadata" => { "promptTokenCount" => 5, "candidatesTokenCount" => 5 }
      })

      @adapter.collect_usage(@session, { "logs/http.log" => log })

      assert_nil @session.reload.usage_statistic
    end

    private

    def mitm_response(host, payload, body: nil, encoding: "text")
      {
        "ts" => "2026-09-12T11:00:00Z",
        "direction" => "response",
        "status_code" => 200,
        "host" => host,
        "path" => "/v1internal:generateContent",
        "body" => body || payload.to_json,
        "body_encoding" => encoding
      }.to_json + "\n"
    end

    def preflight_runtime(auth_content)
      filesystem = {}
      filesystem[@adapter.config_path] = auth_content unless auth_content.nil?
      runtime = ContainerRuntime::FakeRuntime.new(agent_type: "antigravity_cli", filesystem: filesystem)
      [ runtime, runtime.resolve_container("abc123") ]
    end
  end
end
