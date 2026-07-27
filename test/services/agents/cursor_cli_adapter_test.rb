# frozen_string_literal: true

require "test_helper"

module Agents
  class CursorCliAdapterTest < ActiveSupport::TestCase
    setup do
      @adapter = CursorCliAdapter.new
    end

    test "config_path returns cursor auth.json path" do
      assert_equal "/home/cursor/.config/cursor/auth.json", @adapter.config_path
    end

    test "home_dir returns cursor home" do
      assert_equal "/home/cursor", @adapter.home_dir
    end

    test "auth_required_keys returns accessToken" do
      assert_equal %w[accessToken], @adapter.auth_required_keys
    end

    test "auth_complete? returns true with accessToken" do
      content = { "accessToken" => "token123" }.to_json
      assert @adapter.auth_complete?(content)
    end

    test "auth_complete? returns false without accessToken" do
      content = { "refreshToken" => "refresh" }.to_json
      refute @adapter.auth_complete?(content)
    end

    test "extract_credentials extracts token fields" do
      content = {
        "accessToken" => "access123",
        "refreshToken" => "refresh456",
        "otherField" => "ignored"
      }.to_json

      credentials = @adapter.extract_credentials(content)

      assert_equal "access123", credentials["accessToken"]
      assert_equal "refresh456", credentials["refreshToken"]
      refute credentials.key?("otherField")
    end

    test "generate_config returns tokens" do
      credentials = { "accessToken" => "access", "refreshToken" => "refresh" }

      config = @adapter.generate_config(credentials)

      assert_equal "access", config["accessToken"]
      assert_equal "refresh", config["refreshToken"]
    end

    test "generate_config handles missing refreshToken" do
      credentials = { "accessToken" => "access" }

      config = @adapter.generate_config(credentials)

      assert_equal "access", config["accessToken"]
      refute config.key?("refreshToken")
    end

    test "config_path_alt returns alternative cursor auth.json path" do
      assert_equal "/home/cursor/.cursor/auth.json", @adapter.config_path_alt
    end

    test "auth_watch_path returns comma-separated paths" do
      assert_equal "/home/cursor/.config/cursor/auth.json,/home/cursor/.cursor/auth.json", @adapter.auth_watch_path
    end

    test "auth_file_paths returns both auth paths" do
      assert_equal [ "/home/cursor/.config/cursor/auth.json", "/home/cursor/.cursor/auth.json" ], @adapter.auth_file_paths
    end

    test "config_files returns auth, cli-config, and workspace-trust files" do
      credentials = { "accessToken" => "access", "refreshToken" => "refresh" }

      files = @adapter.config_files(credentials, { workspace: "/project" })

      # Primary auth file (XDG path)
      assert files.key?("/home/cursor/.config/cursor/auth.json")
      auth = JSON.parse(files["/home/cursor/.config/cursor/auth.json"])
      assert_equal "access", auth["accessToken"]

      # Alternative auth file
      assert files.key?("/home/cursor/.cursor/auth.json")
      auth_alt = JSON.parse(files["/home/cursor/.cursor/auth.json"])
      assert_equal "access", auth_alt["accessToken"]

      # CLI config
      assert files.key?("/home/cursor/.cursor/cli-config.json")
      cli_config = JSON.parse(files["/home/cursor/.cursor/cli-config.json"])
      assert_equal 1, cli_config["version"]
      assert_includes cli_config["permissions"]["allow"], "Shell(git)"
      assert_includes cli_config["permissions"]["deny"], "Shell(sudo)"
      assert cli_config.dig("network", "useHttp1ForAgent")

      # Workspace trust
      trust_path = "/home/cursor/.cursor/projects/project/.workspace-trusted"
      assert files.key?(trust_path)
      trust = JSON.parse(files[trust_path])
      assert_equal "/project", trust["workspacePath"]
      assert trust["trustedAt"].present?
    end

    test "config_files uses default workspace when not provided" do
      credentials = { "accessToken" => "access" }
      files = @adapter.config_files(credentials)

      trust_path = "/home/cursor/.cursor/projects/workspace/.workspace-trusted"
      assert files.key?(trust_path)
    end

    test "build_rpc_windows pairs http2 Run request and response by x-request-id" do
      log = [
        { ts: "2026-05-21T19:32:30.461Z", direction: "request", path: "/agent.v1.AgentService/Run",
          headers: { "x-request-id" => "req-1" }, _source: "http2-logger" },
        { ts: "2026-05-21T19:32:31.000Z", direction: "response", path: "/agent.v1.AgentService/Run",
          headers: { "x-request-id" => "req-1" }, _source: "http2-logger" }
      ].map(&:to_json).join("\n")

      windows = @adapter.send(:build_rpc_windows, log)

      assert_equal 1, windows.size
      assert_equal "req-1", windows.first[:request_id]
      assert windows.first[:response_ms].present?
    end

    test "build_rpc_windows pairs mitm RunSSE when response omits x-request-id" do
      log = [
        { ts: "2026-05-21T19:43:56.338089Z", direction: "request", path: "/agent.v1.AgentService/RunSSE",
          headers: { "x-request-id" => "req-sse-1" } },
        { ts: "2026-05-21T19:43:57.033Z", direction: "response", status_code: 200,
          path: "/agent.v1.AgentService/RunSSE", _source: "node-http-logger" },
        { ts: "2026-05-21T19:44:02.435065Z", direction: "response", status_code: 200,
          path: "/agent.v1.AgentService/RunSSE", headers: {} }
      ].map(&:to_json).join("\n")

      windows = @adapter.send(:build_rpc_windows, log)

      assert_equal 1, windows.size
      assert_equal "req-sse-1", windows.first[:request_id]
      assert_equal @adapter.send(:parse_iso_to_epoch_ms, "2026-05-21T19:43:57.033Z"), windows.first[:response_ms]
    end

    test "build_rpc_windows ignores http2 requests without a matching response" do
      log = [
        { ts: "2026-05-21T19:32:30.461Z", direction: "request", path: "/agent.v1.AgentService/Run",
          headers: { "x-request-id" => "orphan" }, _source: "http2-logger" }
      ].map(&:to_json).join("\n")

      assert_empty @adapter.send(:build_rpc_windows, log)
    end

    # =========================================================================
    # session_command
    # =========================================================================

    test "session_command returns agent --force without a model" do
      assert_equal "agent --force", @adapter.session_command(mode: "interactive")
      assert_equal "agent --force", @adapter.session_command(mode: "non_interactive", prompt: "do it")
    end

    test "session_command appends a shell-escaped model flag when model provided" do
      assert_equal "agent --force --model gpt-5.1", @adapter.session_command(mode: "interactive", model: "gpt-5.1")
      # Space in the model name must be shell-escaped so it stays one argument.
      assert_equal "agent --force --model claude\\ sonnet", @adapter.session_command(mode: "interactive", model: "claude sonnet")
    end

    # =========================================================================
    # mcp_config
    # =========================================================================

    test "mcp_config emits mcp.json + pre-approvals for stdio and remote servers" do
      project = create(:project, :standalone)
      stdio = create(:mcp_server, :stdio_transport,
                     name: "playwright", command: "npx @playwright/mcp",
                     args: [ "--headless" ], env: { "KEY" => "v" }, scope: project)
      remote = create(:mcp_server, :with_headers,
                      name: "context7", url: "https://mcp.context7.com/v1", scope: project)

      result = @adapter.mcp_config([ stdio, remote ])

      mcp = JSON.parse(result["/workspace/.cursor/mcp.json"])
      servers = mcp["mcpServers"]

      # stdio server: command/args/env, no url. The baked-browser path is injected
      # into every stdio server's env (task #340) and the server's own env is merged
      # on top of it.
      assert_equal "npx @playwright/mcp", servers["playwright"]["command"]
      assert_equal [ "--headless" ], servers["playwright"]["args"]
      assert_equal({ "PLAYWRIGHT_BROWSERS_PATH" => "/opt/playwright-browsers", "KEY" => "v" },
                   servers["playwright"]["env"])
      refute servers["playwright"].key?("url")

      # remote (sse) server: url + headers, no command
      assert_equal "https://mcp.context7.com/v1", servers["context7"]["url"]
      assert_equal({ "Authorization" => "Bearer test-token" }, servers["context7"]["headers"])
      refute servers["context7"].key?("command")

      # One pre-approval per server, "<name>-<16 hex>" (Cursor's approval hash).
      approvals = JSON.parse(result["/home/cursor/.cursor/projects/workspace/mcp-approvals.json"])
      assert_equal 2, approvals.size
      assert(approvals.all? { |a| a.match?(/\A(playwright|context7)-[0-9a-f]{16}\z/) },
             "approvals should be name-hash pairs, got #{approvals.inspect}")
    end

    test "mcp_config pins the Playwright MCP command to the baked version (task #340)" do
      project = create(:project, :standalone)
      stdio = create(:mcp_server, :stdio_transport,
                     name: "playwright", command: "npx",
                     args: [ "@playwright/mcp@latest", "--headless" ], scope: project)

      mcp = JSON.parse(@adapter.mcp_config([ stdio ])["/workspace/.cursor/mcp.json"])
      args = mcp["mcpServers"]["playwright"]["args"]

      pinned = "@playwright/mcp@#{Agents::BaseAdapter::PLAYWRIGHT_MCP_VERSION}"
      assert_equal [ pinned, "--headless" ], args
      # Emitted command cannot float independently of PLAYWRIGHT_MCP_VERSION.
      refute_includes args, "@playwright/mcp@latest"
    end

    # =========================================================================
    # fetch_available_models
    # =========================================================================

    test "fetch_available_models parses the Cursor GetUsableModels response" do
      body = {
        "models" => [
          { "modelId" => "claude-4-sonnet", "displayName" => "Claude 4 Sonnet", "description" => "Balanced" },
          { "modelId" => "gpt-5", "displayName" => "GPT-5" },
          { "displayName" => "no id, dropped" }
        ]
      }.to_json
      stub_request(:post, CursorCliAdapter::CURSOR_MODELS_URL)
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      models = @adapter.fetch_available_models({ "accessToken" => "tok-abc" })

      assert_equal 2, models.size
      assert_equal(
        { model_id: "claude-4-sonnet", display_name: "Claude 4 Sonnet", description: "Balanced" },
        models.first
      )
      # display_name falls back to the model id; description defaults to "".
      assert_equal({ model_id: "gpt-5", display_name: "GPT-5", description: "" }, models.last)
    end

    test "fetch_available_models refreshes the token on 401 and persists the new one" do
      user = create(:user, company: create(:company))
      credential = create(:agent_credential, :cursor_cli, user: user,
                          config_data: { "accessToken" => "stale", "refreshToken" => "refresh-1" })

      models_body = { "models" => [ { "modelId" => "auto", "displayName" => "Auto" } ] }.to_json
      stub_request(:post, CursorCliAdapter::CURSOR_MODELS_URL)
        .to_return(status: 401, body: "")
        .to_return(status: 200, body: models_body, headers: { "Content-Type" => "application/json" })
      stub_request(:post, CursorCliAdapter::CURSOR_AUTH_URL)
        .to_return(status: 200,
                   body: { "access_token" => "fresh-token", "refresh_token" => "refresh-2" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      models = @adapter.fetch_available_models({ "accessToken" => "stale" }, credential: credential)

      assert_equal [ { model_id: "auto", display_name: "Auto", description: "" } ], models
      # Refreshed credentials are persisted for the next session.
      credential.reload
      assert_equal "fresh-token", credential.config_data["accessToken"]
      assert_equal "refresh-2", credential.config_data["refreshToken"]
    end

    # =========================================================================
    # collect_usage — MITM RPC windows correlated with Dashboard API events
    # =========================================================================

    test "collect_usage correlates API events to RPC windows and persists a UsageStatistic" do
      user = create(:user, company: create(:company))
      session = create(:terminal_session, :collected, agent_type: "cursor_cli", user: user)
      create(:agent_credential, :cursor_cli, user: user, config_data: { "accessToken" => "session-token" })

      response_iso = "2026-05-21T19:32:31.000Z"
      response_ms = @adapter.send(:parse_iso_to_epoch_ms, response_iso)
      mitm_log = [
        { ts: "2026-05-21T19:32:30.461Z", direction: "request", path: "/agent.v1.AgentService/Run",
          headers: { "x-request-id" => "req-1" }, _source: "http2-logger" },
        { ts: response_iso, direction: "response", path: "/agent.v1.AgentService/Run",
          headers: { "x-request-id" => "req-1" }, _source: "http2-logger" }
      ].map(&:to_json).join("\n")

      api_events = [
        {
          "timestamp" => (response_ms + 100).to_s,
          "model" => "claude-4-sonnet",
          "tokenUsage" => { "inputTokens" => 1000, "outputTokens" => 200,
                            "cacheReadTokens" => 800, "cacheWriteTokens" => 50, "totalCents" => 3.5 }
        },
        {
          "timestamp" => (response_ms + 200).to_s,
          "model" => "gpt-5",
          "tokenUsage" => { "inputTokens" => 500, "outputTokens" => 100, "totalCents" => 1.5 }
        }
      ]
      stub_request(:post, "https://api2.cursor.sh/aiserver.v1.DashboardService/GetFilteredUsageEvents")
        .to_return(status: 200,
                   body: { "usageEventsDisplay" => api_events }.to_json,
                   headers: { "Content-Type" => "application/json" })

      @adapter.collect_usage(session, { "logs/http.log" => mitm_log })

      stat = session.reload.usage_statistic
      assert stat, "UsageStatistic should be persisted"
      assert_equal 1500, stat.input_tokens
      assert_equal 300, stat.output_tokens
      assert_equal 800, stat.cache_read_tokens
      assert_equal 50, stat.cache_write_tokens
      assert_equal BigDecimal("5.0"), stat.total_cents_precise
      assert_equal 5, stat.cost_cents
      assert_equal %w[claude-4-sonnet gpt-5].sort, stat.models.sort
      assert_equal 2, stat.events_count
      assert_equal 2, stat.events_data.size
      assert_equal "cursor_api", stat.source

      # Raw API result is stashed in session metadata for debugging.
      api_result = session.metadata["usage_api_result"]
      assert_equal 2, api_result["total_fetched"]
      assert_equal 2, api_result["events"].size
    end

    test "collect_usage drops API events that fall outside every RPC window" do
      user = create(:user, company: create(:company))
      session = create(:terminal_session, :collected, agent_type: "cursor_cli", user: user)
      create(:agent_credential, :cursor_cli, user: user, config_data: { "accessToken" => "session-token" })

      response_iso = "2026-05-21T19:32:31.000Z"
      response_ms = @adapter.send(:parse_iso_to_epoch_ms, response_iso)
      mitm_log = [
        { ts: "2026-05-21T19:32:30.461Z", direction: "request", path: "/agent.v1.AgentService/Run",
          headers: { "x-request-id" => "req-1" }, _source: "http2-logger" },
        { ts: response_iso, direction: "response", path: "/agent.v1.AgentService/Run",
          headers: { "x-request-id" => "req-1" }, _source: "http2-logger" }
      ].map(&:to_json).join("\n")

      api_events = [
        { "timestamp" => (response_ms + 100).to_s, "model" => "in-window",
          "tokenUsage" => { "inputTokens" => 10, "totalCents" => 0.1 } },
        # 5s after the response — well past the 1s matching window, so it is ignored.
        { "timestamp" => (response_ms + 5_000).to_s, "model" => "out-of-window",
          "tokenUsage" => { "inputTokens" => 999, "totalCents" => 9.9 } }
      ]
      stub_request(:post, "https://api2.cursor.sh/aiserver.v1.DashboardService/GetFilteredUsageEvents")
        .to_return(status: 200,
                   body: { "usageEventsDisplay" => api_events }.to_json,
                   headers: { "Content-Type" => "application/json" })

      @adapter.collect_usage(session, { "logs/http.log" => mitm_log })

      stat = session.reload.usage_statistic
      assert_equal 1, stat.events_count
      assert_equal 10, stat.input_tokens
      assert_equal [ "in-window" ], stat.models
    end

    # =========================================================================
    # refresh! — proactive-refresh hook (wraps refresh_cursor_token!)
    # =========================================================================

    test "refresh! rotates and persists the token, returning refreshed" do
      user = create(:user, company: create(:company))
      credential = create(:agent_credential, :cursor_cli, user: user,
                          config_data: { "accessToken" => "old", "refreshToken" => "r1" })
      stub_request(:post, CursorCliAdapter::CURSOR_AUTH_URL)
        .to_return(status: 200,
                   body: { access_token: "new", refresh_token: "r2" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      assert_equal({ status: :refreshed, detail: nil }, @adapter.refresh!(credential))
      credential.reload
      assert_equal "new", credential.config_data["accessToken"]
      assert_equal "r2", credential.config_data["refreshToken"]
    end

    test "refresh! returns error when the refresh endpoint fails" do
      user = create(:user, company: create(:company))
      credential = create(:agent_credential, :cursor_cli, user: user,
                          config_data: { "accessToken" => "old", "refreshToken" => "r1" })
      stub_request(:post, CursorCliAdapter::CURSOR_AUTH_URL).to_return(status: 401, body: "")

      result = @adapter.refresh!(credential)

      assert_equal :error, result[:status]
      assert_equal "cursor token refresh failed", result[:detail]
    end

    test "refresh! returns error when no refresh token is present" do
      user = create(:user, company: create(:company))
      credential = create(:agent_credential, :cursor_cli, user: user,
                          config_data: { "accessToken" => "old" })

      assert_equal :error, @adapter.refresh!(credential)[:status]
    end

    test "token_expires_at decodes the JWT exp (ms) from the accessToken" do
      exp = 2.hours.from_now.to_i
      assert_equal exp * 1000, @adapter.token_expires_at({ "accessToken" => jwt_with_exp(exp) })
    end

    test "token_expires_at returns nil when the accessToken is opaque or missing" do
      assert_nil @adapter.token_expires_at({ "accessToken" => "opaque" })
      assert_nil @adapter.token_expires_at({})
    end

    private

    # Minimal unsigned JWT carrying an `exp` claim (seconds).
    def jwt_with_exp(exp_seconds)
      header = Base64.urlsafe_encode64({ alg: "none" }.to_json, padding: false)
      payload = Base64.urlsafe_encode64({ exp: exp_seconds }.to_json, padding: false)
      "#{header}.#{payload}.sig"
    end
  end
end
