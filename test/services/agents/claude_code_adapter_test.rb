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

    test "auth_required_keys returns the two real-token paths" do
      assert_equal %w[primaryApiKey claudeAiOauth.accessToken], @adapter.auth_required_keys
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
      assert_equal "auto", settings.dig("permissions", "defaultMode")
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

    test "config_files defaultMode is auto for non_interactive sessions" do
      files = @adapter.config_files({ "primaryApiKey" => "sk" }, { mode: "non_interactive" })
      settings = JSON.parse(files["/home/claude/.claude/settings.json"])
      assert_equal "auto", settings.dig("permissions", "defaultMode")
    end

    test "config_files defaultMode is auto for interactive sessions" do
      files = @adapter.config_files({ "primaryApiKey" => "sk" }, { mode: "interactive" })
      settings = JSON.parse(files["/home/claude/.claude/settings.json"])
      assert_equal "auto", settings.dig("permissions", "defaultMode")
    end

    test "config_files defaults to auto when mode is absent" do
      files = @adapter.config_files({ "primaryApiKey" => "sk" })
      settings = JSON.parse(files["/home/claude/.claude/settings.json"])
      assert_equal "auto", settings.dig("permissions", "defaultMode")
    end

    test "DesignSync is allow-listed so it runs without a prompt" do
      assert_includes @adapter.allowed_tools([]), "DesignSync"

      files = @adapter.config_files({ "primaryApiKey" => "sk" }, { mode: "non_interactive" })
      settings = JSON.parse(files["/home/claude/.claude/settings.json"])
      assert_includes settings.dig("permissions", "allow"), "DesignSync"
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

    private

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
