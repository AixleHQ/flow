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

    test "session_log_paths returns mitm log path" do
      assert_equal %w[/var/log/mitm/http.log], @adapter.session_log_paths
    end

    # == Auth ==

    test "auth_required_keys returns oauth and api key" do
      assert_equal %w[oauthAccount primaryApiKey], @adapter.auth_required_keys
    end

    test "auth_complete? returns true with oauthAccount" do
      content = { "oauthAccount" => { "id" => "acc-123" } }.to_json
      assert @adapter.auth_complete?(content)
    end

    test "auth_complete? returns true with primaryApiKey" do
      content = { "primaryApiKey" => "sk-xxx" }.to_json
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
        "ignoredField" => "ignored"
      }.to_json

      creds = @adapter.extract_credentials(content)

      assert_equal "sk-key", creds["primaryApiKey"]
      assert_equal "user-1", creds["userID"]
      refute creds.key?("ignoredField")
    end

    # == Config ==

    test "generate_config includes credentials and fixed values" do
      credentials = { "primaryApiKey" => "sk-xxx", "userID" => "u1" }

      config = @adapter.generate_config(credentials)

      assert_equal "sk-xxx", config["primaryApiKey"]
      assert_equal "u1", config["userID"]
      assert_equal true, config["hasCompletedOnboarding"]
      assert_equal "2.1.14", config["lastOnboardingVersion"]
      assert config["projects"].present?
    end

    test "config_files returns main config and settings" do
      credentials = { "primaryApiKey" => "sk-xxx" }

      files = @adapter.config_files(credentials)

      assert files.key?("/home/claude/.claude.json")
      assert files.key?("/home/claude/.claude/settings.json")
      main = JSON.parse(files["/home/claude/.claude.json"])
      assert_equal "sk-xxx", main["primaryApiKey"]
      settings = JSON.parse(files["/home/claude/.claude/settings.json"])
      assert_equal "dontAsk", settings.dig("permissions", "defaultMode")
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

    # == Skills ==

    test "skill_files returns path to content mapping" do
      skills = [
        OpenStruct.new(name: "skill1", content: "# Skill 1"),
        OpenStruct.new(name: "skill2", content: "")
      ]

      files = @adapter.skill_files(skills)

      assert_equal 1, files.size
      assert_equal "# Skill 1", files["/home/claude/.claude/skills/skill1.md"]
      refute files.key?("/home/claude/.claude/skills/skill2.md")
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

    test "tmpfs_paths returns claude and mitmproxy dirs" do
      paths = @adapter.tmpfs_paths

      assert_includes paths, "/home/claude/.claude"
      assert_includes paths, "/home/claude/.mitmproxy"
    end

    test "default_env_vars includes MITM and OTLP settings" do
      Settings.stubs(:otel).returns(OpenStruct.new(endpoint: "http://otel:4318"))

      env = @adapter.default_env_vars(@session)

      assert_equal "/var/log/mitm/http.log", env["MITM_LOG_PATH"]
      assert_equal "api.anthropic.com", env["MITM_TRACKED_DOMAINS"]
      assert_includes env["OTEL_RESOURCE_ATTRIBUTES"], @session.route_token
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
  end
end
