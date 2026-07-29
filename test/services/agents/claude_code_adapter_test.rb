# frozen_string_literal: true

require "test_helper"

module Agents
  class ClaudeCodeAdapterTest < ActiveSupport::TestCase
    setup do
      @adapter = ClaudeCodeAdapter.new
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @session = create(:terminal_session, :running, user: @user, project: @project)
    end

    # == Paths ==

    test "config_path returns claude json path" do
      assert_equal "/home/claude/.claude.json", @adapter.config_path
    end

    test "home_dir returns claude home" do
      assert_equal "/home/claude", @adapter.home_dir
    end

    test "context_file_path returns CLAUDE.md path" do
      assert_equal "/home/claude/.claude/CLAUDE.md", @adapter.context_file_path
    end

    test "session_log_paths returns context and mitm log paths" do
      assert_equal %w[/var/log/context.log /var/log/mitm/http.log], @adapter.session_log_paths
    end

    # == Auth ==

    # Three ways to be finished, any-match: an API key, a claude.ai token, or — since
    # Bedrock produces no token at all — the marker its wizard writes into settings.json.
    test "auth_required_keys covers every way a login can finish" do
      assert_equal %w[primaryApiKey claudeAiOauth.accessToken env.CLAUDE_CODE_USE_BEDROCK],
                   @adapter.auth_required_keys
    end

    test "auth_complete? returns false with only oauthAccount metadata" do
      # oauthAccount lands before the token — relying on it caused a race that
      # captured creds before primaryApiKey/claudeAiOauth was written.
      content = { "oauthAccount" => { "id" => "acc-123" } }.to_json
      refute @adapter.auth_complete?(content)
    end

    test "auth_complete? returns true with primaryApiKey" do
      content = { "primaryApiKey" => "sk-xxx" }.to_json
      assert @adapter.auth_complete?(content)
    end

    test "auth_complete? returns true with claudeAiOauth accessToken" do
      content = { "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-xxx" } }.to_json
      assert @adapter.auth_complete?(content)
    end

    # == design auth kind (all design behavior lives in this adapter) ==

    test "the default (agent) auth kind is a fresh login via the standard hooks" do
      assert_equal @adapter.auth_required_keys, @adapter.auth_required_keys_for("agent")
      assert_empty @adapter.auth_launch_commands_for("agent")
    end

    # The auth container carries no credential, but it does carry the AWS profile — Claude
    # Code's Bedrock wizard lists profiles from ~/.aws/config, and it executes their
    # credential_process during verification. That execution is how we learn the user chose
    # Bedrock inside the TUI, before anything is written to disk.
    test "the default auth kind seeds the platform AWS profile and no credential" do
      files = @adapter.auth_setup_files_for("agent", { "claudeAiOauth" => {} })

      assert_equal [ "/home/claude/.aws/config" ], files.keys
      assert_includes files.values.first, "[profile aixle-bedrock]"
      assert_includes files.values.first, "credential_process = /usr/local/bin/aixle-aws-creds"
    end

    test "design kind watches only for the designOauth block" do
      assert_equal %w[designOauth.accessToken], @adapter.auth_required_keys_for("design")
    end

    test "design kind seeds the existing base login, stripping designOauth (reconnect-safe)" do
      current = {
        "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-base" },
        "designOauth" => { "accessToken" => "sk-ant-oat01-OLD" }
      }
      files = @adapter.auth_setup_files_for("design", current)
      creds = files["/home/claude/.claude/.credentials.json"]

      assert_includes creds, "sk-ant-oat01-base"
      refute_includes creds, "sk-ant-oat01-OLD", "must not seed the design token we're re-minting"
    end

    test "design kind launches claude already running /design-login (one command)" do
      assert_equal [ "claude /design-login" ], @adapter.auth_launch_commands_for("design")
    end

    test "design completion is gated on the designOauth block, not the injected base" do
      base_only = { "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-base" } }.to_json
      refute @adapter.auth_complete_for?("design", base_only)

      with_design = { "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-base" },
                      "designOauth" => { "accessToken" => "sk-ant-oat01-design" } }.to_json
      assert @adapter.auth_complete_for?("design", with_design)
    end

    test "design reconcile adds only the fresh designOauth, never re-scraping the base" do
      current = { "primaryApiKey" => "sk-ant-api-PLATFORM" }
      # A full container scrape also surfaces the injected base AND a stale
      # claudeAiOauth Claude wrote — neither must survive into the stored blob.
      captured = {
        "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-STALE" },
        "designOauth" => { "accessToken" => "sk-ant-oat01-DESIGN-NEW" }
      }
      result = @adapter.reconcile_captured_credentials("design", current, captured)

      assert_equal "sk-ant-api-PLATFORM", result["primaryApiKey"], "base login preserved untouched"
      assert_equal "sk-ant-oat01-DESIGN-NEW", result.dig("designOauth", "accessToken")
      refute result.key?("claudeAiOauth"), "must not resurrect the stale scraped base login"
    end

    test "design reconcile keeps the current credential when the scrape has no designOauth" do
      current = { "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-base" } }
      result = @adapter.reconcile_captured_credentials("design", current, { "designOauth" => {} })

      assert_equal current, result
    end

    test "the default (agent) auth kind reconcile replaces with the fresh scrape" do
      current = { "claudeAiOauth" => { "accessToken" => "old" } }
      captured = { "claudeAiOauth" => { "accessToken" => "new" } }

      assert_equal captured, @adapter.reconcile_captured_credentials("agent", current, captured)
    end

    test "auth_complete? returns false without credentials" do
      content = { "otherField" => "value" }.to_json
      refute @adapter.auth_complete?(content)
    end

    test "extract_credentials extracts allowed keys" do
      content = {
        "oauthAccount" => { "id" => "acc" },
        "primaryApiKey" => "sk-key",
        "userID" => "user-1",
        "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-xxx", "refreshToken" => "sk-ant-ort01-yyy" },
        "ignoredField" => "ignored"
      }.to_json

      creds = @adapter.extract_credentials(content)

      assert_equal "sk-key", creds["primaryApiKey"]
      assert_equal "user-1", creds["userID"]
      assert_equal "sk-ant-oat01-xxx", creds.dig("claudeAiOauth", "accessToken")
      refute creds.key?("ignoredField")
    end

    # == Config ==

    test "generate_config includes credentials and fixed values" do
      credentials = { "primaryApiKey" => "sk-xxx", "userID" => "u1" }

      config = @adapter.generate_config(credentials)

      assert_equal "sk-xxx", config["primaryApiKey"]
      assert_equal "u1", config["userID"]
      assert config["hasCompletedOnboarding"]
      assert_equal "2.1.14", config["lastOnboardingVersion"]
      assert config["projects"].present?
    end

    test "config_files returns main config and settings" do
      credentials = { "primaryApiKey" => "sk-xxx" }

      files = @adapter.config_files(credentials)

      assert files.key?("/home/claude/.claude.json")
      assert files.key?("/home/claude/.claude/settings.json")
      refute files.key?("/home/claude/.claude/.credentials.json")
      main = JSON.parse(files["/home/claude/.claude.json"])
      assert_equal "sk-xxx", main["primaryApiKey"]
      settings = JSON.parse(files["/home/claude/.claude/settings.json"])
      assert_equal "bypassPermissions", settings.dig("permissions", "defaultMode")
      assert_equal "90000", settings.dig("env", "MCP_TIMEOUT")
    end

    test "config_files writes claudeAiOauth to .credentials.json (OAuth path)" do
      credentials = {
        "oauthAccount" => { "emailAddress" => "u@x.com" },
        "claudeAiOauth" => {
          "accessToken" => "sk-ant-oat01-xxx",
          "refreshToken" => "sk-ant-ort01-yyy",
          "expiresAt" => 1_777_000_000_000
        }
      }

      files = @adapter.config_files(credentials)

      assert files.key?("/home/claude/.claude/.credentials.json")
      creds_file = JSON.parse(files["/home/claude/.claude/.credentials.json"])
      assert_equal "sk-ant-oat01-xxx", creds_file.dig("claudeAiOauth", "accessToken")
      assert_equal "sk-ant-ort01-yyy", creds_file.dig("claudeAiOauth", "refreshToken")

      # claudeAiOauth must NOT leak into ~/.claude.json — Claude Code reads it from .credentials.json only
      main = JSON.parse(files["/home/claude/.claude.json"])
      refute main.key?("claudeAiOauth")
      assert_equal "u@x.com", main.dig("oauthAccount", "emailAddress")
    end

    test "config_files skips .credentials.json when claudeAiOauth has no accessToken" do
      credentials = { "primaryApiKey" => "sk", "claudeAiOauth" => { "refreshToken" => "only-refresh" } }

      files = @adapter.config_files(credentials)

      refute files.key?("/home/claude/.claude/.credentials.json")
    end

    test "designOauth is extracted and written to .credentials.json, never to .claude.json" do
      config = {
        "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-base", "scopes" => %w[user:inference] },
        "designOauth" => {
          "accessToken" => "sk-ant-oat01-design",
          "refreshToken" => "sk-ant-ort01-d",
          "scopes" => %w[user:design:read user:design:write]
        }
      }.to_json

      extracted = @adapter.extract_credentials(config)
      assert extracted.key?("designOauth"), "designOauth must be persisted from the container config"

      files = @adapter.config_files(extracted)
      creds = JSON.parse(files["/home/claude/.claude/.credentials.json"])
      assert_equal "sk-ant-oat01-design", creds.dig("designOauth", "accessToken")
      assert_equal %w[user:design:read user:design:write], creds.dig("designOauth", "scopes")
      assert_equal "sk-ant-oat01-base", creds.dig("claudeAiOauth", "accessToken")

      # designOauth (like claudeAiOauth) must NOT leak into ~/.claude.json
      main = JSON.parse(files["/home/claude/.claude.json"])
      refute main.key?("designOauth")
      refute main.key?("claudeAiOauth")
    end

    test "merge_refreshed_credentials adds designOauth even when claudeAiOauth is unchanged" do
      current  = { "claudeAiOauth" => { "accessToken" => "base", "expiresAt" => 1000 } }
      incoming = { "claudeAiOauth" => { "accessToken" => "base", "expiresAt" => 1000 },
                   "designOauth" => { "accessToken" => "design", "expiresAt" => 2000 } }

      merged = @adapter.merge_refreshed_credentials(current, incoming)

      assert_equal "design", merged.dig("designOauth", "accessToken")
      assert_equal "base", merged.dig("claudeAiOauth", "accessToken")
    end

    test "merge_refreshed_credentials never wipes a stored designOauth the session lacks" do
      current  = { "claudeAiOauth" => { "accessToken" => "base", "expiresAt" => 1000 },
                   "designOauth" => { "accessToken" => "design", "expiresAt" => 2000 } }
      # A session without /design-login refreshes only the base token.
      incoming = { "claudeAiOauth" => { "accessToken" => "base2", "expiresAt" => 3000 } }

      merged = @adapter.merge_refreshed_credentials(current, incoming)

      assert_equal "base2", merged.dig("claudeAiOauth", "accessToken") # newer base wins
      assert_equal "design", merged.dig("designOauth", "accessToken")  # stored design preserved
    end

    test "merge_refreshed_credentials keeps the fresher token per block (no rotation downgrade)" do
      current  = { "claudeAiOauth" => { "accessToken" => "new", "expiresAt" => 5000 },
                   "designOauth" => { "accessToken" => "d-new", "expiresAt" => 5000 } }
      incoming = { "claudeAiOauth" => { "accessToken" => "old", "expiresAt" => 1000 },
                   "designOauth" => { "accessToken" => "d-old", "expiresAt" => 1000 } }

      merged = @adapter.merge_refreshed_credentials(current, incoming)

      assert_equal "new", merged.dig("claudeAiOauth", "accessToken")
      assert_equal "d-new", merged.dig("designOauth", "accessToken")
    end

    test "base adapter merge_refreshed_credentials guards on token_expires_at (wholesale replace)" do
      base = Agents::BaseAdapter.new # default token_expires_at is nil
      # No expiry info => replace wholesale with incoming.
      assert_equal({ "a" => 2 }, base.merge_refreshed_credentials({ "a" => 1 }, { "a" => 2 }))

      # With expiries: keep current when incoming is not newer.
      base.stubs(:token_expires_at).with({ "e" => 5 }).returns(5)
      base.stubs(:token_expires_at).with({ "e" => 3 }).returns(3)
      assert_equal({ "e" => 5 }, base.merge_refreshed_credentials({ "e" => 5 }, { "e" => 3 }))
    end

    test "config_files defaultMode is bypassPermissions for non_interactive sessions" do
      files = @adapter.config_files({ "primaryApiKey" => "sk" }, { mode: "non_interactive" })
      settings = JSON.parse(files["/home/claude/.claude/settings.json"])
      assert_equal "bypassPermissions", settings.dig("permissions", "defaultMode")
    end

    test "config_files defaultMode is bypassPermissions for interactive sessions" do
      files = @adapter.config_files({ "primaryApiKey" => "sk" }, { mode: "interactive" })
      settings = JSON.parse(files["/home/claude/.claude/settings.json"])
      assert_equal "bypassPermissions", settings.dig("permissions", "defaultMode")
    end

    test "settings pre-accept the bypass-permissions startup warning" do
      files = @adapter.config_files({ "primaryApiKey" => "sk" }, { mode: "interactive" })
      settings = JSON.parse(files["/home/claude/.claude/settings.json"])
      # skipDangerousModePermissionPrompt is the key Claude Code writes when the
      # user clicks through the warning; without it, bypassPermissions still blocks.
      assert_equal true, settings["skipDangerousModePermissionPrompt"] # rubocop:disable Minitest/AssertTruthy
      assert_equal true, settings["bypassPermissionsWarningAccepted"] # rubocop:disable Minitest/AssertTruthy
    end

    test "config_files defaults to bypassPermissions when mode is absent" do
      files = @adapter.config_files({ "primaryApiKey" => "sk" })
      settings = JSON.parse(files["/home/claude/.claude/settings.json"])
      assert_equal "bypassPermissions", settings.dig("permissions", "defaultMode")
    end

    test "DesignSync is allow-listed in both session modes" do
      assert_includes @adapter.allowed_tools([]), "DesignSync"

      %w[interactive non_interactive].each do |mode|
        files = @adapter.config_files({ "primaryApiKey" => "sk" }, { mode: mode })
        settings = JSON.parse(files["/home/claude/.claude/settings.json"])
        assert_includes settings.dig("permissions", "allow"), "DesignSync"
      end
    end

    test "config_files includes MCP permissions when enabled_mcp_servers provided" do
      credentials = { "primaryApiKey" => "sk" }
      workflow_config = { enabled_mcp_servers: %w[context7 tavily] }

      files = @adapter.config_files(credentials, workflow_config)

      settings = JSON.parse(files["/home/claude/.claude/settings.json"])
      allow = settings.dig("permissions", "allow")
      assert_includes allow, "mcp__context7"
      assert_includes allow, "mcp__tavily"
    end

    # == Session ==

    test "session_command returns claude for interactive" do
      assert_equal "claude", @adapter.session_command(mode: "interactive")
    end

    test "session_command returns claude for non_interactive" do
      assert_equal "claude", @adapter.session_command(mode: "non_interactive")
    end

    # == Tools ==

    test "allowed_tools returns builtin tools" do
      tools = @adapter.allowed_tools([])

      assert_includes tools, "Task"
      assert_includes tools, "Bash"
      assert_includes tools, "Read"
      assert_includes tools, "Edit"
    end

    test "allowed_tools includes MCP tools when names provided" do
      tools = @adapter.allowed_tools(%w[context7 tavily])

      assert_includes tools, "mcp__context7"
      assert_includes tools, "mcp__tavily"
    end

    # == MCP ==

    test "mcp_config builds mcpServers json" do
      servers = [
        OpenStruct.new(name: "ctx", transport: "http", url: "https://mcp.example.com", headers: nil),
        OpenStruct.new(name: "stdio", transport: "stdio", url: nil, headers: nil)
      ]

      files = @adapter.mcp_config(servers)

      assert files.key?("/workspace/.mcp.json")
      config = JSON.parse(files["/workspace/.mcp.json"])
      assert_equal "http", config["mcpServers"]["ctx"]["type"]
      assert_equal "https://mcp.example.com", config["mcpServers"]["ctx"]["url"]
      assert_equal "stdio", config["mcpServers"]["stdio"]["type"]
      # The baked Playwright browsers path is injected into every stdio server (task #340).
      assert_equal "/opt/playwright-browsers",
                   config["mcpServers"]["stdio"]["env"]["PLAYWRIGHT_BROWSERS_PATH"]
    end

    test "mcp_config pins the Playwright MCP command to the baked version (task #340)" do
      servers = [
        OpenStruct.new(name: "playwright", transport: "stdio",
                       command: "npx", args: [ "@playwright/mcp@latest", "--headless" ])
      ]

      config = JSON.parse(@adapter.mcp_config(servers)["/workspace/.mcp.json"])
      args = config["mcpServers"]["playwright"]["args"]

      pinned = "@playwright/mcp@#{Agents::BaseAdapter::PLAYWRIGHT_MCP_VERSION}"
      assert_equal [ pinned, "--headless" ], args
      # Emitted command cannot float independently of PLAYWRIGHT_MCP_VERSION.
      refute_includes args, "@playwright/mcp@latest"
    end

    # == Env ==

    test "default_env_vars includes MITM and OTLP settings" do
      Settings.stubs(:otel).returns(OpenStruct.new(endpoint: "http://otel:4318"))

      env = @adapter.default_env_vars(@session)

      assert_equal "/var/log/mitm/http.log", env["MITM_LOG_PATH"]
      assert_equal "api.anthropic.com", env["MITM_TRACKED_DOMAINS"]
      assert_includes env["OTEL_RESOURCE_ATTRIBUTES"], @session.route_token
      assert_equal "90000", env["MCP_TIMEOUT"]
    end

    # == Ingest Usage ==

    test "ingest_usage returns accepted when no events" do
      payload = { "resourceMetrics" => [] }

      result = @adapter.ingest_usage(payload, @session)

      assert_equal :accepted, result
    end

    test "ingest_usage returns accepted when token blank" do
      result = @adapter.ingest_usage({}, @session)

      assert_equal :accepted, result
    end

    test "ingest_usage persists and returns ok when valid OTLP payload" do
      payload = {
        "resourceMetrics" => [ {
          "resource" => { "attributes" => [] },
          "scopeMetrics" => [ {
            "metrics" => [ {
              "name" => "claude_code.token.usage",
              "sum" => {
                "dataPoints" => [ {
                  "attributes" => [
                    { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                    { "key" => "type", "value" => { "stringValue" => "input" } },
                    { "key" => "model", "value" => { "stringValue" => "claude-3-5" } }
                  ],
                  "asInt" => "100"
                } ]
              }
            } ]
          } ]
        } ]
      }

      result = @adapter.ingest_usage(payload, @session)

      assert_equal :ok, result
      @session.reload
      stat = @session.usage_statistic
      assert stat.present?
      assert_equal 100, stat.input_tokens
    end

    # == Available Models ==

    test "fetch_available_models_with_source falls back when no credentials" do
      result = @adapter.fetch_available_models_with_source({})

      assert_equal :fallback, result[:source]
      assert_equal ClaudeCodeAdapter::FALLBACK_CLAUDE_MODELS, result[:models]
    end

    test "fetch_available_models_with_source uses x-api-key for API key credentials" do
      captured = stub_models_response([ { "id" => "claude-opus-4-8", "display_name" => "Claude Opus 4.8" } ])

      result = @adapter.fetch_available_models_with_source({ "primaryApiKey" => "sk-key" })

      assert_equal :api, result[:source]
      assert_equal "claude-opus-4-8", result[:models].first[:model_id]
      assert_equal "sk-key", captured[:req]["x-api-key"]
      assert_nil captured[:req]["authorization"]
    end

    test "fetch_available_models_with_source uses OAuth bearer when only claudeAiOauth present" do
      captured = stub_models_response([ { "id" => "claude-sonnet-4-6", "display_name" => "Claude Sonnet 4.6" } ])

      result = @adapter.fetch_available_models_with_source({ "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-x" } })

      assert_equal :api, result[:source]
      assert_equal "claude-sonnet-4-6", result[:models].first[:model_id]
      assert_equal "Bearer sk-ant-oat01-x", captured[:req]["authorization"]
      assert_equal "oauth-2025-04-20", captured[:req]["anthropic-beta"]
      assert_nil captured[:req]["x-api-key"]
    end

    test "fetch_available_models_with_source falls back on non-success response" do
      response = mock("response")
      response.stubs(:is_a?).with(Net::HTTPSuccess).returns(false)
      http = mock("http")
      http.stubs(:request).returns(response)
      Net::HTTP.stubs(:start).yields(http).returns(response)

      result = @adapter.fetch_available_models_with_source({ "primaryApiKey" => "sk-key" })

      assert_equal :fallback, result[:source]
    end

    test "ingest_usage supports legacy metric names" do
      payload = {
        "resourceMetrics" => [ {
          "resource" => { "attributes" => [] },
          "scopeMetrics" => [ {
            "metrics" => [ {
              "name" => "terminal.session.tokens",
              "sum" => {
                "dataPoints" => [ {
                  "attributes" => [
                    { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                    { "key" => "type", "value" => { "stringValue" => "output" } }
                  ],
                  "asInt" => "50"
                } ]
              }
            } ]
          } ]
        } ]
      }

      result = @adapter.ingest_usage(payload, @session)

      assert_equal :ok, result
      @session.reload
      assert_equal 50, @session.usage_statistic.output_tokens
    end

    # == token_expires_at (soonest across blocks) ==

    test "token_expires_at returns the soonest expiry across oauth blocks" do
      creds = {
        "claudeAiOauth" => { "expiresAt" => 3_000 },
        "designOauth" => { "expiresAt" => 1_000 }
      }

      assert_equal 1_000, @adapter.token_expires_at(creds)
    end

    test "token_expires_at returns the single block's expiry when only one is present" do
      assert_equal 5_000, @adapter.token_expires_at({ "claudeAiOauth" => { "expiresAt" => 5_000 } })
    end

    test "token_expires_at coerces a string expiresAt to an integer" do
      assert_equal 1_234, @adapter.token_expires_at({ "designOauth" => { "expiresAt" => "1234" } })
    end

    test "token_expires_at returns nil when no oauth block carries an expiry" do
      assert_nil @adapter.token_expires_at({ "primaryApiKey" => "sk" })
    end

    # == refresh! (proactive server-side refresh) ==

    test "refresh! returns not_needed when no oauth block carries a refresh token" do
      cred = create(:agent_credential, :claude_code, user: @user,
                    config_data: { "primaryApiKey" => "sk" })

      assert_equal({ status: :not_needed, detail: nil }, @adapter.refresh!(cred))
    end

    test "refresh! returns not_needed when the token is not near expiry" do
      cred = create(:agent_credential, :claude_code, user: @user, config_data: {
        "claudeAiOauth" => { "accessToken" => "a", "refreshToken" => "r", "expiresAt" => ms_from_now(60 * 60 * 1000) }
      })

      assert_equal({ status: :not_needed, detail: nil }, @adapter.refresh!(cred))
    end

    test "refresh! refreshes a claudeAiOauth block near expiry and persists rotated tokens" do
      soon = ms_from_now(5 * 60 * 1000) # within the 15-min margin
      cred = create(:agent_credential, :claude_code, user: @user, config_data: {
        "claudeAiOauth" => {
          "accessToken" => "old-a", "refreshToken" => "old-r",
          "expiresAt" => soon, "scopes" => %w[user:inference]
        }
      })
      stub_request(:post, ClaudeCodeAdapter::OAUTH_TOKEN_URL)
        .with(body: { grant_type: "refresh_token", client_id: ClaudeCodeAdapter::BASE_OAUTH_CLIENT_ID, refresh_token: "old-r" })
        .to_return(status: 200,
                   body: { access_token: "new-a", refresh_token: "new-r", expires_in: 3_600, scope: "user:inference" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = @adapter.refresh!(cred)

      assert_equal :refreshed, result[:status]
      block = cred.reload.config_data["claudeAiOauth"]
      assert_equal "new-a", block["accessToken"]
      assert_equal "new-r", block["refreshToken"]
      assert_operator block["expiresAt"], :>, soon
    end

    test "refresh! uses the designOauth block's own clientId and preserves refreshToken/scopes when the server omits them" do
      soon = ms_from_now(5 * 60 * 1000)
      cred = create(:agent_credential, :claude_code, user: @user, config_data: {
        "designOauth" => {
          "accessToken" => "old-d", "refreshToken" => "old-dr", "expiresAt" => soon,
          "clientId" => "design-client", "scopes" => %w[user:design:read]
        }
      })
      stub_request(:post, ClaudeCodeAdapter::OAUTH_TOKEN_URL)
        .with(body: { grant_type: "refresh_token", client_id: "design-client", refresh_token: "old-dr" })
        .to_return(status: 200,
                   body: { access_token: "new-d", expires_in: 3_600 }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = @adapter.refresh!(cred)

      assert_equal :refreshed, result[:status]
      block = cred.reload.config_data["designOauth"]
      assert_equal "new-d", block["accessToken"]
      assert_equal "old-dr", block["refreshToken"]        # server omitted rotation → keep old
      assert_equal "design-client", block["clientId"]     # preserved
      assert_equal %w[user:design:read], block["scopes"]  # scope omitted → keep previous
    end

    test "refresh! returns error and persists nothing when the token endpoint responds non-2xx" do
      soon = ms_from_now(5 * 60 * 1000)
      cred = create(:agent_credential, :claude_code, user: @user, config_data: {
        "claudeAiOauth" => { "accessToken" => "a", "refreshToken" => "r", "expiresAt" => soon }
      })
      stub_request(:post, ClaudeCodeAdapter::OAUTH_TOKEN_URL).to_return(status: 400, body: "bad")

      result = @adapter.refresh!(cred)

      assert_equal :error, result[:status]
      assert_match(/claudeAiOauth refresh failed/, result[:detail])
      assert_equal "a", cred.reload.config_data.dig("claudeAiOauth", "accessToken")
    end

    test "refresh! counts as refreshed when one block succeeds and another fails, leaving the failed block intact" do
      soon = ms_from_now(5 * 60 * 1000)
      cred = create(:agent_credential, :claude_code, user: @user, config_data: {
        "claudeAiOauth" => { "accessToken" => "base-a", "refreshToken" => "base-r", "expiresAt" => soon },
        "designOauth" => { "accessToken" => "d-a", "refreshToken" => "d-r", "expiresAt" => soon, "clientId" => "design-client" }
      })
      stub_request(:post, ClaudeCodeAdapter::OAUTH_TOKEN_URL)
        .with(body: { grant_type: "refresh_token", client_id: ClaudeCodeAdapter::BASE_OAUTH_CLIENT_ID, refresh_token: "base-r" })
        .to_return(status: 200,
                   body: { access_token: "base-a2", refresh_token: "base-r2", expires_in: 3_600 }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:post, ClaudeCodeAdapter::OAUTH_TOKEN_URL)
        .with(body: { grant_type: "refresh_token", client_id: "design-client", refresh_token: "d-r" })
        .to_return(status: 500, body: "boom")

      result = @adapter.refresh!(cred)

      assert_equal :refreshed, result[:status]
      assert_match(/designOauth refresh failed/, result[:detail])
      reloaded = cred.reload.config_data
      assert_equal "base-a2", reloaded.dig("claudeAiOauth", "accessToken")
      assert_equal "d-a", reloaded.dig("designOauth", "accessToken") # failed block left intact
    end

    # == Amazon Bedrock (bring-your-own cloud account) ==

    test "config_files writes no aws config and no bedrock env without an awsBedrock block" do
      files = @adapter.config_files({ "primaryApiKey" => "sk-ant-x" })

      assert_not_includes files.keys, "/home/claude/.aws/config"
      assert_not_includes settings_env(files).keys, "CLAUDE_CODE_USE_BEDROCK"
    end

    test "an awsBedrock block without a region is ignored" do
      files = @adapter.config_files({ "awsBedrock" => { "profile" => "aixle" } })

      assert_not_includes files.keys, "/home/claude/.aws/config"
      assert_not_includes settings_env(files).keys, "CLAUDE_CODE_USE_BEDROCK"
    end

    test "bedrock settings env enables bedrock, pins models, and sets the guardrail header" do
      files = @adapter.config_files({ "awsBedrock" => bedrock_block })
      env = settings_env(files)

      assert_equal "1", env["CLAUDE_CODE_USE_BEDROCK"]
      assert_equal "us-east-1", env["AWS_REGION"]
      assert_equal "aixle", env["AWS_PROFILE"]
      assert_equal "120000", env["CLAUDE_CODE_AWS_CHAIN_RESOLVE_TIMEOUT_MS"]
      assert_equal "us.anthropic.claude-sonnet-4-6", env["ANTHROPIC_DEFAULT_SONNET_MODEL"]
      assert_equal "us.anthropic.claude-haiku-4-5", env["ANTHROPIC_DEFAULT_HAIKU_MODEL"]
      assert_equal(
        "X-Amzn-Bedrock-GuardrailIdentifier: gr-123\nX-Amzn-Bedrock-GuardrailVersion: 2",
        env["ANTHROPIC_CUSTOM_HEADERS"]
      )
      # MCP_TIMEOUT must survive the merge — bedrock env is additive, not a replacement.
      assert env["MCP_TIMEOUT"].present?
    end

    test "bedrock block carries availableModels and awsAuthRefresh into settings" do
      settings = settings_hash(@adapter.config_files({ "awsBedrock" => bedrock_block }))

      assert_equal %w[opus sonnet haiku], settings["availableModels"]
      assert_equal "/usr/local/bin/aixle-aws-connect", settings["awsAuthRefresh"]
    end

    # Regression: Claude Code treats availableModels as an allowlist and answers anything
    # outside it with "Model … is restricted by your organization's settings. Using
    # us.anthropic.claude-sonnet-4-5 instead." A list captured at connect time then silently
    # downgraded a session the user had pinned to the account's own application profile —
    # and moved the spend onto a shared system profile.
    test "the model this session runs on is always in the allowlist" do
      arn = "arn:aws:bedrock:us-east-1:541894707537:application-inference-profile/aae1a165gwk4"

      settings = settings_hash(
        @adapter.config_files({ "awsBedrock" => bedrock_block }, { model: arn })
      )

      assert_includes settings["availableModels"], arn
      assert_equal "opus", settings["availableModels"].first, "the stored list keeps its order"
      assert_equal arn, settings["model"]
    end

    test "a model already in the allowlist is not duplicated" do
      settings = settings_hash(
        @adapter.config_files({ "awsBedrock" => bedrock_block }, { model: "sonnet" })
      )

      assert_equal %w[opus sonnet haiku], settings["availableModels"]
    end

    # No stored list means Claude Code's own picker is unrestricted; injecting a one-entry
    # allowlist would narrow it to exactly one model.
    test "a connection with no stored list gets no allowlist at all" do
      block = bedrock_block.except("available_models")

      settings = settings_hash(@adapter.config_files({ "awsBedrock" => block }, { model: "sonnet" }))

      assert_nil settings["availableModels"]
    end

    test "chain resolve timeout is overridable per connection" do
      block = bedrock_block.merge("chain_resolve_timeout_ms" => 300_000)
      env = settings_env(@adapter.config_files({ "awsBedrock" => block }))

      assert_equal "300000", env["CLAUDE_CODE_AWS_CHAIN_RESOLVE_TIMEOUT_MS"]
    end

    test "a bearer token connection sets AWS_BEARER_TOKEN_BEDROCK and writes no profile" do
      block = { "region" => "us-east-1", "bearer_token" => "bedrock-api-key-xyz" }
      files = @adapter.config_files({ "awsBedrock" => block })
      env = settings_env(files)

      assert_equal "bedrock-api-key-xyz", env["AWS_BEARER_TOKEN_BEDROCK"]
      assert_not_includes env.keys, "AWS_PROFILE"
      assert_not_includes files.keys, "/home/claude/.aws/config"
    end

    test "aws config is written to the literal home path with a credential_process profile" do
      files = @adapter.config_files({ "awsBedrock" => bedrock_block })
      config = files["/home/claude/.aws/config"]

      assert_equal <<~INI, config
        [profile aixle]
        credential_process = /usr/local/bin/aixle-aws-creds
        region = us-east-1
      INI
    end

    test "an sso_session connection renders both the session and profile sections" do
      block = {
        "region" => "us-east-1",
        "profile" => "aixle",
        "sso_session" => {
          "start_url" => "https://example.awsapps.com/start",
          "region" => "us-west-2",
          "account_id" => "111122223333",
          "role_name" => "BedrockUser"
        }
      }
      config = @adapter.config_files({ "awsBedrock" => block })["/home/claude/.aws/config"]

      assert_equal <<~INI, config
        [sso-session aixle]
        sso_start_url = https://example.awsapps.com/start
        sso_region = us-west-2
        sso_registration_scopes = sso:account:access

        [profile aixle]
        sso_session = aixle
        sso_account_id = 111122223333
        sso_role_name = BedrockUser
        region = us-east-1
      INI
    end

    # == Bedrock login completion and what the wizard's choices leave behind ==

    test "a settings file carrying the bedrock marker counts as a finished login" do
      assert @adapter.auth_complete?({ "env" => { "CLAUDE_CODE_USE_BEDROCK" => "1" } }.to_json)
      assert_not @adapter.auth_complete?({ "env" => { "AWS_REGION" => "us-east-1" } }.to_json)
      assert_not @adapter.auth_complete?({ "permissions" => {} }.to_json)
    end

    test "settings.json is watched, so the marker is visible to the watcher" do
      assert_includes @adapter.auth_file_paths, "/home/claude/.claude/settings.json"
      assert_includes @adapter.auth_watch_path, "/home/claude/.claude/settings.json"
    end

    # Pins are the load-bearing part: the settings file is regenerated from the connection
    # every session, and an unpinned Bedrock deployment resolves to Opus and bills at Opus
    # rates.
    test "the wizard's region, profile and model pins are captured" do
      settings = {
        "env" => {
          "CLAUDE_CODE_USE_BEDROCK" => "1",
          "AWS_REGION" => "eu-central-1",
          "AWS_PROFILE" => "dbp-aixle",
          "ANTHROPIC_DEFAULT_SONNET_MODEL" => "us.anthropic.claude-sonnet-4-6",
          "ANTHROPIC_DEFAULT_OPUS_MODEL" => "arn:aws:bedrock:eu-central-1:1:application-inference-profile/x"
        },
        "availableModels" => %w[opus sonnet]
      }

      block = @adapter.extract_settings_config(settings.to_json).fetch("awsBedrock")

      assert_equal "eu-central-1", block["region"]
      assert_equal "dbp-aixle", block["profile"]
      assert_equal "us.anthropic.claude-sonnet-4-6", block.dig("models", "sonnet")
      assert_equal "arn:aws:bedrock:eu-central-1:1:application-inference-profile/x", block.dig("models", "opus")
      assert_equal %w[opus sonnet], block["available_models"]
    end

    # Same pattern as primaryApiKey: whatever the CLI persisted during login is sliced and
    # kept, or a user who pastes a key at the wizard's prompt loses it with the container.
    test "a bedrock api key configured in the wizard is captured and restored" do
      settings = { "env" => { "CLAUDE_CODE_USE_BEDROCK" => "1", "AWS_BEARER_TOKEN_BEDROCK" => "bedrock-api-key-x" } }

      block = @adapter.extract_settings_config(settings.to_json).fetch("awsBedrock")
      assert_equal "bedrock-api-key-x", block["bearer_token"]

      env = settings_env(@adapter.config_files({ "awsBedrock" => block.merge("region" => "us-east-1") }))
      assert_equal "bedrock-api-key-x", env["AWS_BEARER_TOKEN_BEDROCK"]
    end

    test "long-term access keys are captured and restored" do
      settings = {
        "env" => {
          "CLAUDE_CODE_USE_BEDROCK" => "1", "AWS_REGION" => "us-east-1",
          "AWS_ACCESS_KEY_ID" => "AKIAEXAMPLE", "AWS_SECRET_ACCESS_KEY" => "secret-part"
        }
      }

      block = @adapter.extract_settings_config(settings.to_json).fetch("awsBedrock")
      assert_equal "AKIAEXAMPLE", block.dig("static_credentials", "access_key_id")

      env = settings_env(@adapter.config_files({ "awsBedrock" => block }))
      assert_equal "AKIAEXAMPLE", env["AWS_ACCESS_KEY_ID"]
      assert_equal "secret-part", env["AWS_SECRET_ACCESS_KEY"]
    end

    # Storing a temporary STS session would hand the next session credentials that already
    # expired — and Bedrock fails opaquely, so that is worse than having no connection.
    test "temporary sts credentials are not captured" do
      settings = {
        "env" => {
          "CLAUDE_CODE_USE_BEDROCK" => "1",
          "AWS_ACCESS_KEY_ID" => "ASIATEMP", "AWS_SECRET_ACCESS_KEY" => "s", "AWS_SESSION_TOKEN" => "temp"
        }
      }

      block = @adapter.extract_settings_config(settings.to_json).fetch("awsBedrock")

      assert_nil block["static_credentials"]
      assert_not_includes block.to_json, "ASIATEMP"
    end

    # Not a Bedrock credential, and the Console path is already covered by primaryApiKey in
    # .claude.json. Keeping it here would also fight the conflicting-env scrub.
    test "an anthropic api key is not captured from the bedrock settings" do
      settings = { "env" => { "CLAUDE_CODE_USE_BEDROCK" => "1", "ANTHROPIC_API_KEY" => "sk-ant-secret" } }

      captured = @adapter.extract_settings_config(settings.to_json)

      assert_not_includes captured.to_json, "sk-ant-secret"
    end

    test "a settings file with no bedrock marker yields nothing" do
      assert_empty @adapter.extract_settings_config({ "env" => { "AWS_REGION" => "us-east-1" } }.to_json)
    end

    # The connection is stored server-side and never appears in the container, so the
    # default full-replace would destroy it — refresh token included — the first time an
    # auth session completed.
    test "completing an auth session preserves the stored cloud connection" do
      current = {
        "awsBedrock" => {
          "region" => "us-east-1", "profile" => "aixle-bedrock",
          "credential_process" => "/usr/local/bin/aixle-aws-creds",
          "identity_center" => { "account_id" => "1", "role_name" => "R", "token" => { "refresh_token" => "keep-me" } }
        }
      }

      # What a completed Bedrock auth session actually captures: the wizard's marker, and
      # nothing that could stand in for the server-side connection.
      captured = { "awsBedrock" => { "region" => "us-east-1", "profile" => "aixle-bedrock" } }

      merged = @adapter.reconcile_captured_credentials("agent", current, captured)

      assert_equal "keep-me", merged.dig("awsBedrock", "identity_center", "token", "refresh_token")
    end

    test "the wizard's choices fold into the stored connection without touching its credentials" do
      current = {
        "awsBedrock" => {
          "region" => "us-east-1", "profile" => "aixle-bedrock",
          "credential_process" => "/usr/local/bin/aixle-aws-creds",
          "models" => { "haiku" => "us.anthropic.claude-haiku-4-5" },
          "identity_center" => { "account_id" => "1", "role_name" => "R" }
        }
      }
      captured = { "awsBedrock" => { "region" => "eu-central-1", "models" => { "sonnet" => "pinned-sonnet" } } }

      block = @adapter.reconcile_captured_credentials("agent", current, captured).fetch("awsBedrock")

      assert_equal "eu-central-1", block["region"], "the wizard decided the region"
      assert_equal "pinned-sonnet", block.dig("models", "sonnet")
      assert_equal "us.anthropic.claude-haiku-4-5", block.dig("models", "haiku"), "existing pins survive"
      assert_equal "1", block.dig("identity_center", "account_id")
      assert_equal "/usr/local/bin/aixle-aws-creds", block["credential_process"]
    end

    # == Bedrock model catalogue ==
    #
    # A static list can never name an account's own application inference profiles, and those
    # ARNs are exactly what an enterprise deployment pins.

    # An account that curates its models scopes bedrock:InvokeModel to its own application
    # profile ARNs, which leaves every system-defined profile visible but denied. Offering
    # both is how an unusable model reaches the picker.
    test "a bedrock connection lists what the account can actually invoke" do
      credential = connect_bedrock
      catalog = stub_catalog([
        FakeAwsModelCatalog.system_profile("us.anthropic.claude-sonnet-4-6", name: "Claude Sonnet 4.6"),
        FakeAwsModelCatalog.application_profile(
          "arn:aws:bedrock:us-east-1:111122223333:application-inference-profile/flow", name: "Flow"
        )
      ], credential: credential)

      result = @adapter.fetch_available_models_with_source(credential.config_data, credential: credential)

      assert_equal :api, result[:source]
      assert_equal [ "arn:aws:bedrock:us-east-1:111122223333:application-inference-profile/flow" ],
                   result[:models].map { |m| m[:model_id] }
      assert_equal 1, catalog.calls
    end

    # Regression: a Fable system profile sorted above the account's own profiles and was
    # picked first, then failed on the first invocation because the permission set allowed
    # only the four ids behind its application profiles.
    test "a newer shared profile does not displace the account's own profiles" do
      credential = connect_bedrock
      stub_catalog([
        FakeAwsModelCatalog.system_profile(
          "us.anthropic.claude-fable-5",
          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-fable-5"
        ),
        FakeAwsModelCatalog.application_profile(
          "arn:aws:bedrock:us-east-1:1:application-inference-profile/flow-opus-4-8", name: "flow opus-4-8",
          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-opus-4-8"
        )
      ])

      models = @adapter.fetch_available_models_with_source(credential.config_data, credential: credential)[:models]

      assert_equal [ "arn:aws:bedrock:us-east-1:1:application-inference-profile/flow-opus-4-8" ],
                   models.map { |m| m[:model_id] }
    end

    test "models the CLI cannot run are left out" do
      credential = connect_bedrock
      stub_catalog([
        FakeAwsModelCatalog.system_profile("us.anthropic.claude-sonnet-4-6"),
        FakeAwsModelCatalog.non_anthropic_profile("us.amazon.nova-2")
      ])

      models = @adapter.fetch_available_models_with_source(credential.config_data, credential: credential)[:models]

      assert_equal [ "us.anthropic.claude-sonnet-4-6" ], models.map { |m| m[:model_id] }
    end

    # Claude 3.x carries a 2x extended-access surcharge on Bedrock and retires on its own
    # calendar. A real account lists 25 profiles with those inside.
    test "the surcharged legacy generation is dropped" do
      credential = connect_bedrock
      stub_catalog([
        FakeAwsModelCatalog.system_profile("us.anthropic.claude-3-sonnet-20240229-v1:0",
                                          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"),
        FakeAwsModelCatalog.system_profile("us.anthropic.claude-3-5-sonnet-20241022-v2:0",
                                          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0"),
        FakeAwsModelCatalog.system_profile("us.anthropic.claude-sonnet-4-6",
                                          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-sonnet-4-6")
      ])

      models = @adapter.fetch_available_models_with_source(credential.config_data, credential: credential)[:models]

      assert_equal [ "us.anthropic.claude-sonnet-4-6" ], models.map { |m| m[:model_id] }
    end

    # The same model is listed once per geography. A global profile costs ~10% less than the
    # regional one and draws on a larger pool, so offering both invites paying more by
    # accident.
    test "only the cheapest geography of a model is offered" do
      credential = connect_bedrock
      stub_catalog([
        FakeAwsModelCatalog.system_profile("us.anthropic.claude-opus-5",
                                          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-opus-5"),
        FakeAwsModelCatalog.system_profile("global.anthropic.claude-opus-5",
                                          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-opus-5"),
        FakeAwsModelCatalog.system_profile("eu.anthropic.claude-opus-5",
                                          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-opus-5")
      ])

      models = @adapter.fetch_available_models_with_source(credential.config_data, credential: credential)[:models]

      assert_equal [ "global.anthropic.claude-opus-5" ], models.map { |m| m[:model_id] }
    end

    # A model AWS offers only regionally must still be offered.
    test "a model with no global profile keeps its regional one" do
      credential = connect_bedrock
      stub_catalog([
        FakeAwsModelCatalog.system_profile("us.anthropic.claude-haiku-4-5",
                                          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-haiku-4-5")
      ])

      models = @adapter.fetch_available_models_with_source(credential.config_data, credential: credential)[:models]

      assert_equal [ "us.anthropic.claude-haiku-4-5" ], models.map { |m| m[:model_id] }
    end

    # An account's own profiles are distinct objects, not geographic variants of one model.
    test "application profiles are never collapsed into each other" do
      credential = connect_bedrock
      stub_catalog([
        FakeAwsModelCatalog.application_profile(
          "arn:aws:bedrock:us-east-1:1:application-inference-profile/plan", name: "Plan",
          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-opus-4-8"
        ),
        FakeAwsModelCatalog.application_profile(
          "arn:aws:bedrock:us-east-1:1:application-inference-profile/flow", name: "Flow",
          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-opus-4-8"
        )
      ])

      models = @adapter.fetch_available_models_with_source(credential.config_data, credential: credential)[:models]

      assert_equal 2, models.size
    end

    test "the newest generation comes first so the obvious pick is the right one" do
      credential = connect_bedrock
      stub_catalog([
        FakeAwsModelCatalog.system_profile("us.anthropic.claude-sonnet-4-5",
                                          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-sonnet-4-5"),
        FakeAwsModelCatalog.system_profile("us.anthropic.claude-opus-5",
                                          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-opus-5"),
        FakeAwsModelCatalog.system_profile("us.anthropic.claude-opus-4-8",
                                          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-opus-4-8")
      ])

      models = @adapter.fetch_available_models_with_source(credential.config_data, credential: credential)[:models]

      assert_equal [ "us.anthropic.claude-opus-5", "us.anthropic.claude-opus-4-8", "us.anthropic.claude-sonnet-4-5" ],
                   models.map { |m| m[:model_id] }
    end

    # The container reads its allowlist from the credential, so a list left as it was at
    # connect time holds a session started weeks later to models the account has since
    # replaced. This is the only path that asks AWS what it can invoke today.
    test "listing models refreshes the allowlist stored on the credential" do
      credential = connect_bedrock
      arn = "arn:aws:bedrock:us-east-1:111122223333:application-inference-profile/flow"
      stub_catalog([ FakeAwsModelCatalog.application_profile(arn, name: "Flow") ], credential: credential)

      @adapter.fetch_available_models_with_source(credential.config_data, credential: credential)

      assert_equal [ arn ], credential.reload.config_data.dig("awsBedrock", "available_models")
    end

    test "an unchanged list is not written back" do
      credential = connect_bedrock
      arn = "arn:aws:bedrock:us-east-1:111122223333:application-inference-profile/flow"
      credential.update!(config_data: credential.config_data.deep_merge(
        "awsBedrock" => { "available_models" => [ arn ] }
      ))
      stub_catalog([ FakeAwsModelCatalog.application_profile(arn, name: "Flow") ], credential: credential)

      assert_no_changes -> { credential.reload.updated_at } do
        @adapter.fetch_available_models_with_source(credential.config_data, credential: credential)
      end
    end

    # A permission set without bedrock:ListInferenceProfiles is common. A model picker is not
    # worth breaking a page over.
    test "a denied catalogue falls back to the static list instead of raising" do
      credential = connect_bedrock
      catalog = stub_catalog([])
      catalog.raise_on_list = CloudAuth::DeniedError

      result = @adapter.fetch_available_models_with_source(credential.config_data, credential: credential)

      assert_equal :fallback, result[:source]
      assert result[:models].any?
    end

    # A key typed into the CLI wizard never reaches us in a form we can sign a control-plane
    # call with.
    test "a bearer-token connection uses the static list" do
      credential = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code",
                                                  { "awsBedrock" => { "region" => "us-east-1",
                                                                      "bearer_token" => "k" } })

      result = @adapter.fetch_available_models_with_source(credential.config_data, credential: credential)

      assert_equal :fallback, result[:source]
    end

    # == Exactly one inference credential ==
    #
    # Claude Code picks its provider from env, so a second stored credential would sit there
    # doing nothing while nobody could say which one a request used.

    test "connecting bedrock in an auth session drops an anthropic-side login" do
      current = { "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-old" }, "primaryApiKey" => "sk-ant-old" }
      captured = { "awsBedrock" => { "region" => "us-east-1", "profile" => "aixle-bedrock" } }

      merged = @adapter.reconcile_captured_credentials("agent", current, captured)

      assert merged["awsBedrock"].present?
      assert_nil merged["claudeAiOauth"]
      assert_nil merged["primaryApiKey"]
    end

    test "logging in with claude.ai drops a bedrock connection" do
      current = { "awsBedrock" => { "region" => "us-east-1", "identity_center" => { "account_id" => "1" } } }
      captured = { "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-new" } }

      merged = @adapter.reconcile_captured_credentials("agent", current, captured)

      assert_equal "sk-ant-oat01-new", merged.dig("claudeAiOauth", "accessToken")
      assert_nil merged["awsBedrock"]
    end

    # Design authorizes separately from inference, so changing where tokens are billed must
    # not cost the user their design login.
    test "the design token survives a change of inference credential" do
      current = {
        "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-old" },
        "designOauth" => { "accessToken" => "sk-ant-design" }
      }
      captured = { "awsBedrock" => { "region" => "us-east-1" } }

      merged = @adapter.reconcile_captured_credentials("agent", current, captured)

      assert_equal "sk-ant-design", merged.dig("designOauth", "accessToken")
      assert merged["awsBedrock"].present?
      assert_nil merged["claudeAiOauth"]
    end

    # A working session chooses nothing. Applying the exclusivity rule to its read-back would
    # delete the connection simply because the container never held it.
    test "a working session read-back never drops a stored credential" do
      current = {
        "awsBedrock" => { "region" => "us-east-1", "identity_center" => { "account_id" => "1" } },
        "designOauth" => { "accessToken" => "sk-ant-design" }
      }
      incoming = { "awsBedrock" => { "region" => "us-east-1", "profile" => "aixle-bedrock" } }

      merged = @adapter.merge_refreshed_credentials(current, incoming)

      assert_equal "1", merged.dig("awsBedrock", "identity_center", "account_id")
      assert_equal "sk-ant-design", merged.dig("designOauth", "accessToken")
    end

    test "only the active inference credential is rendered into the container" do
      files = @adapter.config_files({
        "awsBedrock" => bedrock_block,
        "primaryApiKey" => "sk-ant-should-not-ship",
        "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-should-not-ship" },
        "designOauth" => { "accessToken" => "sk-ant-design" }
      })

      assert_not_includes files.fetch("/home/claude/.claude.json"), "sk-ant-should-not-ship"
      creds = files["/home/claude/.claude/.credentials.json"]
      assert_not_includes creds.to_s, "oat01-should-not-ship"
      assert_includes creds.to_s, "sk-ant-design", "design ships alongside any provider"
    end

    # == Conflicting env ==

    test "no env is declared conflicting without a bedrock connection" do
      assert_empty @adapter.conflicting_env_keys({ "primaryApiKey" => "sk-ant-x" })
    end

    # A leftover ANTHROPIC_API_KEY shadows Bedrock, and Claude Code hides Bedrock errors,
    # so the symptom is an agent that simply never answers.
    test "a bedrock connection declares the env that would shadow it" do
      keys = @adapter.conflicting_env_keys({ "awsBedrock" => bedrock_block })

      assert_includes keys, "ANTHROPIC_API_KEY"
      assert_includes keys, "ANTHROPIC_AUTH_TOKEN"
      assert_includes keys, "ANTHROPIC_BASE_URL"
      assert_includes keys, "CLAUDE_CODE_USE_VERTEX"
      assert_includes keys, "CLAUDE_CODE_USE_FOUNDRY"
    end

    # The Bedrock gateway override must survive — it is how a customer points Claude Code
    # at their own LLM gateway in front of Bedrock.
    test "the bedrock gateway override is not treated as conflicting" do
      assert_not_includes @adapter.conflicting_env_keys({ "awsBedrock" => bedrock_block }),
                          "ANTHROPIC_BEDROCK_BASE_URL"
    end

    # == Vending key in process env ==

    test "no vending key is injected for a working session without a cloud connection" do
      env = @adapter.default_env_vars(agent_session)

      assert_not_includes env.keys, "AIXLE_CLOUD_KEY"
      assert_not_includes env.keys, "AIXLE_CLOUD_CREDENTIALS_URL"
    end

    # An auth container is where the user picks Bedrock in Claude Code's own wizard. The
    # helper has to be able to answer "no connection yet" from there — that answer is the
    # signal that opens the connect step in the browser.
    test "an auth session gets the vending env even with no connection at all" do
      env = @adapter.default_env_vars(@session)

      assert_equal "auth_setup", @session.session_type
      assert_equal CloudAuth::SessionKey.generate(@session), env["AIXLE_CLOUD_KEY"]
      assert_equal Settings.cloud.credentials_url, env["AIXLE_CLOUD_CREDENTIALS_URL"]
    end

    test "a credential_process connection injects the vending url and a per-session key" do
      AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", { "awsBedrock" => bedrock_block })
      session = agent_session

      env = @adapter.default_env_vars(session)

      assert_equal Settings.cloud.credentials_url, env["AIXLE_CLOUD_CREDENTIALS_URL"]
      assert_equal CloudAuth::SessionKey.generate(session), env["AIXLE_CLOUD_KEY"]
    end

    test "a bearer-token connection needs no vending key" do
      AgentCredential.from_artifacts(@user.id, @company.id, "claude_code",
                                     { "awsBedrock" => { "region" => "us-east-1", "bearer_token" => "x" } })

      assert_not_includes @adapter.default_env_vars(agent_session).keys, "AIXLE_CLOUD_KEY"
    end

    test "sso_region falls back to the bedrock region when not given separately" do
      block = {
        "region" => "eu-central-1",
        "profile" => "aixle",
        "sso_session" => { "start_url" => "https://example.awsapps.com/start" }
      }
      config = @adapter.config_files({ "awsBedrock" => block })["/home/claude/.aws/config"]

      assert_includes config, "sso_region = eu-central-1"
    end

    private

    def connect_bedrock
      AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", {
        "awsBedrock" => {
          "region" => "us-east-1", "profile" => "aixle-bedrock",
          "credential_process" => "/usr/local/bin/aixle-aws-creds",
          "identity_center" => {
            "sso_region" => "us-west-2", "account_id" => "111122223333", "role_name" => "BedrockUser",
            "registration" => { "client_id" => "c", "expires_at" => 60.days.from_now.iso8601 },
            "token" => { "access_token" => "t", "refresh_token" => "r", "expires_at" => 1.hour.from_now.iso8601 }
          }
        }
      })
    end

    # `credential:` is pinned deliberately. A bare `.stubs(:new)` accepts any arguments, so it
    # answered a call site that had drifted to a signature the real vendor no longer has —
    # the failure only showed up as a silently static model list in the browser.
    def stub_catalog(profiles, credential: nil)
      vended = CloudAuth::AwsCredentialVendor::Vended.new(
        access_key_id: "ASIAFAKE", secret_access_key: "s", session_token: "t", expiration: 1.hour.from_now
      )
      vendor = mock("vendor")
      vendor.stubs(:call).returns(vended)
      expectation = CloudAuth::AwsCredentialVendor.stubs(:new)
      expectation = expectation.with(credential: credential) if credential
      expectation.returns(vendor)

      catalog = FakeAwsModelCatalog.new(region: "us-east-1", access_key_id: "ASIAFAKE",
                                       secret_access_key: "s", session_token: "t")
      catalog.profiles = profiles
      CloudAuth::AwsModelCatalog.stubs(:new).returns(catalog)
      catalog
    end

    def agent_session
      create(:terminal_session, :agent_session, :running, user: @user, project: @project)
    end

    def bedrock_block
      {
        "region" => "us-east-1",
        "profile" => "aixle",
        "credential_process" => "/usr/local/bin/aixle-aws-creds",
        "auth_refresh_command" => "/usr/local/bin/aixle-aws-connect",
        "available_models" => %w[opus sonnet haiku],
        "models" => {
          "sonnet" => "us.anthropic.claude-sonnet-4-6",
          "haiku" => "us.anthropic.claude-haiku-4-5"
        },
        "guardrail" => { "identifier" => "gr-123", "version" => 2 }
      }
    end

    def settings_hash(files)
      JSON.parse(files.fetch("/home/claude/.claude/settings.json"))
    end

    def settings_env(files)
      settings_hash(files).fetch("env")
    end

    # Epoch-ms `offset_ms` into the future (matches the adapter's now_ms basis).
    def ms_from_now(offset_ms)
      (Time.current.to_f * 1000).to_i + offset_ms
    end

    # Stub Net::HTTP to return a successful /v1/models response and capture the
    # outgoing request so header/auth assertions can be made.
    def stub_models_response(data)
      captured = {}
      response = mock("response")
      response.stubs(:is_a?).with(Net::HTTPSuccess).returns(true)
      response.stubs(:body).returns({ "data" => data }.to_json)

      http = mock("http")
      http.stubs(:request).with { |req| captured[:req] = req; true }.returns(response)
      Net::HTTP.stubs(:start).yields(http).returns(response)

      captured
    end
  end
end
