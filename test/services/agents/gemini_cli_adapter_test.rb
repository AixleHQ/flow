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
      assert_equal "auto_edit", settings.dig("tools", "approvalMode")
      assert_equal true, settings.dig("tools", "autoAccept") # rubocop:disable Minitest/AssertTruthy
    end

    test "auth_setup_files pre-trusts the workspace so auth does not prompt" do
      files = @adapter.auth_setup_files

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

    test "ingest_usage persists metric token breakdown and cost" do
      payload = {
        "resourceMetrics" => [ {
          "resource" => { "attributes" => [] },
          "scopeMetrics" => [ {
            "metrics" => [
              {
                "name" => "gemini_cli.token.usage",
                "sum" => {
                  "dataPoints" => [
                    {
                      "attributes" => [
                        { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                        { "key" => "type", "value" => { "stringValue" => "input" } },
                        { "key" => "model", "value" => { "stringValue" => "gemini-2.5-pro" } }
                      ],
                      "asInt" => "100",
                      "timeUnixNano" => "1700000000000000000"
                    },
                    {
                      "attributes" => [
                        { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                        { "key" => "type", "value" => { "stringValue" => "output" } },
                        { "key" => "model", "value" => { "stringValue" => "gemini-2.5-pro" } }
                      ],
                      "asInt" => "40",
                      "timeUnixNano" => "1700000000000000000"
                    },
                    {
                      "attributes" => [
                        { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                        { "key" => "type", "value" => { "stringValue" => "cacheRead" } },
                        { "key" => "model", "value" => { "stringValue" => "gemini-2.5-pro" } }
                      ],
                      "asInt" => "60",
                      "timeUnixNano" => "1700000000000000000"
                    }
                  ]
                }
              },
              {
                "name" => "gemini_cli.cost.usage",
                "sum" => {
                  "dataPoints" => [ {
                    "attributes" => [
                      { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                      { "key" => "model", "value" => { "stringValue" => "gemini-2.5-pro" } }
                    ],
                    "asDouble" => 0.123456
                  } ]
                }
              }
            ]
          } ]
        } ]
      }

      result = @adapter.ingest_usage(payload, @session)

      assert_equal :ok, result
      @session.reload
      stat = @session.usage_statistic

      assert_equal 100, stat.input_tokens
      assert_equal 40, stat.output_tokens
      assert_equal 60, stat.cache_read_tokens
      assert_equal 0, stat.cache_write_tokens
      assert_equal BigDecimal("12.3456"), stat.total_cents_precise
      assert_equal 13, stat.cost_cents
      assert_equal [ "gemini-2.5-pro" ], stat.models
      assert_equal 1, stat.events_count
      assert_equal 200, stat.tokens
    end

    test "ingest_usage falls back to OTLP logs when metrics are absent" do
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
      payload = {
        "resourceMetrics" => [ {
          "resource" => { "attributes" => [] },
          "scopeMetrics" => [ {
            "metrics" => [ {
              "name" => "gemini_cli.token.usage",
              "sum" => {
                "dataPoints" => [ {
                  "attributes" => [
                    { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                    { "key" => "type", "value" => { "stringValue" => "input" } }
                  ],
                  "asInt" => "10"
                } ]
              }
            } ]
          } ]
        } ]
      }

      first = @adapter.ingest_usage(payload, @session)
      second = @adapter.ingest_usage(payload, @session)

      assert_equal :ok, first
      assert_equal :ok, second

      @session.reload
      stat = @session.usage_statistic
      assert_equal 20, stat.input_tokens
      assert_equal 2, stat.events_count
      assert_equal 2, stat.events_data.size
    end

    test "ingest_usage stores multiple models when one metric scope includes multiple models" do
      payload = {
        "resourceMetrics" => [ {
          "resource" => { "attributes" => [] },
          "scopeMetrics" => [ {
            "metrics" => [ {
              "name" => "gemini_cli.token.usage",
              "sum" => {
                "dataPoints" => [
                  {
                    "attributes" => [
                      { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                      { "key" => "model", "value" => { "stringValue" => "gemini-2.5-flash-lite" } },
                      { "key" => "type", "value" => { "stringValue" => "input" } }
                    ],
                    "asInt" => "100"
                  },
                  {
                    "attributes" => [
                      { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                      { "key" => "model", "value" => { "stringValue" => "gemini-3-flash-preview" } },
                      { "key" => "type", "value" => { "stringValue" => "input" } }
                    ],
                    "asInt" => "200"
                  }
                ]
              }
            } ]
          } ]
        } ]
      }

      result = @adapter.ingest_usage(payload, @session)

      assert_equal :ok, result
      @session.reload
      stat = @session.usage_statistic
      assert_equal %w[gemini-2.5-flash-lite gemini-3-flash-preview].sort, stat.models.sort
      assert_equal 300, stat.input_tokens
      assert_equal 2, stat.events_count
      assert_equal 2, stat.events_data.size
    end

    test "ingest_usage maps gemini token types to claude-style breakdown buckets" do
      payload = {
        "resourceMetrics" => [ {
          "resource" => { "attributes" => [] },
          "scopeMetrics" => [ {
            "metrics" => [ {
              "name" => "gemini_cli.token.usage",
              "sum" => {
                "dataPoints" => [
                  {
                    "attributes" => [
                      { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                      { "key" => "model", "value" => { "stringValue" => "gemini-2.5-flash" } },
                      { "key" => "type", "value" => { "stringValue" => "input" } }
                    ],
                    "asInt" => "10"
                  },
                  {
                    "attributes" => [
                      { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                      { "key" => "model", "value" => { "stringValue" => "gemini-2.5-flash" } },
                      { "key" => "type", "value" => { "stringValue" => "output" } }
                    ],
                    "asInt" => "20"
                  },
                  {
                    "attributes" => [
                      { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                      { "key" => "model", "value" => { "stringValue" => "gemini-2.5-flash" } },
                      { "key" => "type", "value" => { "stringValue" => "cache" } }
                    ],
                    "asInt" => "30"
                  },
                  {
                    "attributes" => [
                      { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                      { "key" => "model", "value" => { "stringValue" => "gemini-2.5-flash" } },
                      { "key" => "type", "value" => { "stringValue" => "thought" } }
                    ],
                    "asInt" => "40"
                  },
                  {
                    "attributes" => [
                      { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                      { "key" => "model", "value" => { "stringValue" => "gemini-2.5-flash" } },
                      { "key" => "type", "value" => { "stringValue" => "tool" } }
                    ],
                    "asInt" => "50"
                  },
                  {
                    "attributes" => [
                      { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } },
                      { "key" => "model", "value" => { "stringValue" => "gemini-2.5-flash" } },
                      { "key" => "type", "value" => { "stringValue" => "cacheCreation" } }
                    ],
                    "asInt" => "60"
                  }
                ]
              }
            } ]
          } ]
        } ]
      }

      result = @adapter.ingest_usage(payload, @session)

      assert_equal :ok, result
      @session.reload
      stat = @session.usage_statistic

      assert_equal 10, stat.input_tokens
      # output + thought + tool
      assert_equal 110, stat.output_tokens
      # cache token type maps to cacheReadTokens
      assert_equal 30, stat.cache_read_tokens
      # cacheCreation maps to cacheWriteTokens
      assert_equal 60, stat.cache_write_tokens
      assert_equal 210, stat.tokens
    end
  end
end
