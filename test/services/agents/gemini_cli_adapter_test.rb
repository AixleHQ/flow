# frozen_string_literal: true

require "test_helper"

module Agents
  class GeminiCliAdapterTest < ActiveSupport::TestCase
    setup do
      @adapter = GeminiCliAdapter.new
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @session = create(:terminal_session, :running, user: @user, project: @project)
    end

    test "config_path returns gemini-credentials.json path" do
      assert_equal "/home/gemini/.gemini/gemini-credentials.json", @adapter.config_path
    end

    test "home_dir returns gemini home" do
      assert_equal "/home/gemini", @adapter.home_dir
    end

    test "auth_watch_path points at the credential file, not settings.json" do
      assert_equal "/home/gemini/.gemini/gemini-credentials.json", @adapter.auth_watch_path
    end

    test "auth_required_keys uses the existence sentinel" do
      assert_equal %w[__present__], @adapter.auth_required_keys
    end

    test "auth_complete? is true for a non-blank encrypted credential blob" do
      # gemini-credentials.json is encrypted (iv:authTag:ciphertext), not JSON.
      assert @adapter.auth_complete?("a1b2:c3d4:e5f6deadbeef")
    end

    test "auth_complete? is false for settings.json (auth-method marker only)" do
      content = { "security" => { "auth" => { "selectedType" => "gemini-api-key" } } }.to_json
      refute @adapter.auth_complete?(content)
    end

    test "auth_complete? is false for blank content" do
      refute @adapter.auth_complete?("")
      refute @adapter.auth_complete?("   ")
    end

    test "extract_credentials returns empty hash" do
      content = { "access_token" => "access123", "refresh_token" => "refresh456" }.to_json

      credentials = @adapter.extract_credentials(content)

      assert_equal({}, credentials)
    end

    test "generate_config returns credentials as-is" do
      credentials = { "refresh_token" => "refresh", "access_token" => "access" }

      config = @adapter.generate_config(credentials)

      assert_equal credentials, config
    end

    test "config_files returns settings file with api-key auth type" do
      credentials = { "api_key" => "test-key" }

      files = @adapter.config_files(credentials)

      # Only settings file (API key is passed via env var)
      assert files.key?("/home/gemini/.gemini/settings.json")
      settings = JSON.parse(files["/home/gemini/.gemini/settings.json"])
      assert_equal "gemini-api-key", settings.dig("security", "auth", "selectedType")
      # Exact JSON booleans are the contract: the adapter deliberately writes
      # `false`/`true` into settings.json; a missing key (nil) must fail here.
      assert_equal false, settings.dig("security", "folderTrust", "enabled") # rubocop:disable Minitest/RefuteFalse
      refute settings.dig("general").key?("defaultApprovalMode")
      refute settings.dig("tools").key?("approvalMode")
      refute settings.dig("tools").key?("autoAccept")
    end

    test "auth_setup_files selects API-key auth and pre-trusts the workspace" do
      files = @adapter.auth_setup_files

      settings = JSON.parse(files["/home/gemini/.gemini/settings.json"])
      assert_equal "gemini-api-key", settings.dig("security", "auth", "selectedType")
      refute settings.dig("general").key?("defaultApprovalMode")
      assert files.key?("/home/gemini/.gemini/trustedFolders.json")
      trusted = JSON.parse(files["/home/gemini/.gemini/trustedFolders.json"])
      assert_equal "TRUST_FOLDER", trusted["/workspace"]
    end

    test "config_files pre-trusts the workspace for agent sessions" do
      files = @adapter.config_files({ "api_key" => "test-key" })

      assert files.key?("/home/gemini/.gemini/trustedFolders.json")
      trusted = JSON.parse(files["/home/gemini/.gemini/trustedFolders.json"])
      assert_equal "TRUST_FOLDER", trusted["/workspace"]
    end

    test "config_files trusts a custom workspace path when provided" do
      files = @adapter.config_files({ "api_key" => "k" }, { workspace: "/srv/app" })

      trusted = JSON.parse(files["/home/gemini/.gemini/trustedFolders.json"])
      assert_equal "TRUST_FOLDER", trusted["/srv/app"]
    end

    test "required_env_fields returns empty array" do
      assert_equal [], @adapter.required_env_fields
    end

    test "session_command uses yolo mode for all sessions" do
      assert_equal "gemini --yolo", @adapter.session_command(mode: "interactive")
      assert_equal "gemini --yolo", @adapter.session_command(mode: "non_interactive")
      assert_equal "gemini --model gemini-2.5-pro --yolo",
                   @adapter.session_command(mode: "non_interactive", model: "gemini-2.5-pro")
    end

    test "env_vars_from_metadata returns empty hash" do
      metadata = { "google_cloud_project" => "my-project-123" }

      env_vars = @adapter.env_vars_from_metadata(metadata)

      assert_equal({}, env_vars)
    end

    test "ingest_usage returns accepted when no OTLP usage events found" do
      payload = { "resourceMetrics" => [], "resourceLogs" => [] }

      result = @adapter.ingest_usage(payload, @session)

      assert_equal :accepted, result
    end

    test "ingest_usage ignores the cumulative token metric" do
      # Every export repeats the running total, and the same response also arrives as a
      # gemini_cli.api_response log: counting this too would double the session.
      payload = {
        "resourceMetrics" => [ {
          "resource" => { "attributes" => [ session_token_attribute ] },
          "scopeMetrics" => [ {
            "metrics" => [ {
              "name" => "gemini_cli.token.usage",
              "sum" => {
                "aggregationTemporality" => "AGGREGATION_TEMPORALITY_CUMULATIVE",
                "dataPoints" => [ {
                  "attributes" => [ { "key" => "type", "value" => { "stringValue" => "input" } } ],
                  "asInt" => "100"
                } ]
              }
            } ]
          } ]
        } ]
      }

      assert_equal :accepted, @adapter.ingest_usage(payload, @session)
      assert_nil @session.reload.usage_statistic
    end

    test "ingest_usage counts an api_response log, generated thoughts and tool tokens as output" do
      payload = {
        "resourceLogs" => [ {
          "resource" => { "attributes" => [] },
          "scopeLogs" => [ {
            "logRecords" => [ {
              "timeUnixNano" => "1700000000000001000",
              "attributes" => [
                { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                { "key" => "event.name", "value" => { "stringValue" => "gemini_cli.api_response" } },
                { "key" => "model", "value" => { "stringValue" => "gemini-2.5-flash" } },
                { "key" => "input_token_count", "value" => { "intValue" => "11" } },
                { "key" => "output_token_count", "value" => { "intValue" => "7" } },
                { "key" => "cached_content_token_count", "value" => { "intValue" => "5" } },
                { "key" => "thoughts_token_count", "value" => { "intValue" => "3" } },
                { "key" => "tool_token_count", "value" => { "intValue" => "2" } },
                { "key" => "cost_usd", "value" => { "doubleValue" => 0.01 } }
              ]
            } ]
          } ]
        } ]
      }

      result = @adapter.ingest_usage(payload, @session)

      assert_equal :ok, result
      @session.reload
      stat = @session.usage_statistic

      assert_equal 11, stat.input_tokens
      assert_equal 12, stat.output_tokens
      assert_equal 5, stat.cache_read_tokens
      assert_equal 1, stat.cost_cents
      assert_equal BigDecimal("1.0"), stat.total_cents_precise
      assert_equal [ "gemini-2.5-flash" ], stat.models
      assert_equal 1, stat.events_count
    end

    test "ingest_usage appends new events to existing usage statistic" do
      payload = api_response_logs({ model: "gemini-2.5-pro", input: 10 })

      first = @adapter.ingest_usage(payload, @session)
      second = @adapter.ingest_usage(payload, @session)

      assert_equal :ok, first
      assert_equal :ok, second
      stat = @session.reload.usage_statistic
      assert_equal 20, stat.input_tokens
      assert_equal 2, stat.events_count
      assert_equal 2, stat.events_data.size
    end

    test "ingest_usage stores each model a batch of responses used" do
      payload = api_response_logs({ model: "gemini-2.5-flash-lite", input: 100 },
                                  { model: "gemini-3-flash-preview", input: 200 })

      assert_equal :ok, @adapter.ingest_usage(payload, @session)
      stat = @session.reload.usage_statistic
      assert_equal %w[gemini-2.5-flash-lite gemini-3-flash-preview].sort, stat.models.sort
      assert_equal 300, stat.input_tokens
      assert_equal 2, stat.events_count
    end

    test "default_env_vars injects the API key of the session's company only" do
      other_company = create(:company)
      create(:company_membership, user: @user, company: other_company)
      create(:agent_credential, user: @user, company: other_company, agent_type: "gemini_cli",
                                config_data: { "api_key" => "other-tenant-key" })

      assert_nil @adapter.default_env_vars(@session)["GEMINI_API_KEY"]

      create(:agent_credential, user: @user, company: @company, agent_type: "gemini_cli",
                                config_data: { "api_key" => "mine" })

      assert_equal "mine", @adapter.default_env_vars(@session)["GEMINI_API_KEY"]
    end

    test "mcp_config pins the Playwright MCP command to the baked version (task #340)" do
      servers = [
        OpenStruct.new(name: "playwright", transport: "stdio",
                       command: "npx", args: [ "@playwright/mcp@latest", "--headless" ])
      ]

      settings = JSON.parse(@adapter.mcp_config(servers)["/home/gemini/.gemini/settings.json"])
      args = settings["mcpServers"]["playwright"]["args"]

      pinned = "@playwright/mcp@#{BaseAdapter::PLAYWRIGHT_MCP_VERSION}"
      assert_equal [ pinned, "--headless" ], args
      # Emitted command cannot float independently of PLAYWRIGHT_MCP_VERSION.
      refute_includes args, "@playwright/mcp@latest"
    end

    private

    def session_token_attribute
      { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } }
    end

    def api_response_logs(*responses)
      records = responses.map do |response|
        { "timeUnixNano" => "1700000000000001000",
          "attributes" => [
            { "key" => "event.name", "value" => { "stringValue" => "gemini_cli.api_response" } },
            { "key" => "model", "value" => { "stringValue" => response[:model] } },
            { "key" => "input_token_count", "value" => { "intValue" => response[:input].to_s } }
          ] }
      end
      { "resourceLogs" => [ { "resource" => { "attributes" => [ session_token_attribute ] },
                              "scopeLogs" => [ { "logRecords" => records } ] } ] }
    end
  end
end
