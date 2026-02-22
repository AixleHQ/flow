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

    test "config_path returns gemini oauth_creds.json path" do
      assert_equal "/home/gemini/.gemini/oauth_creds.json", @adapter.config_path
    end

    test "home_dir returns gemini home" do
      assert_equal "/home/gemini", @adapter.home_dir
    end

    test "auth_required_keys returns refresh_token" do
      assert_equal %w[refresh_token], @adapter.auth_required_keys
    end

    test "auth_complete? returns true with refresh_token" do
      content = { "refresh_token" => "refresh123" }.to_json
      assert @adapter.auth_complete?(content)
    end

    test "auth_complete? returns false without refresh_token" do
      content = { "access_token" => "access" }.to_json
      refute @adapter.auth_complete?(content)
    end

    test "extract_credentials extracts oauth fields" do
      content = {
        "access_token" => "access123",
        "refresh_token" => "refresh456",
        "scope" => "email profile",
        "token_type" => "Bearer",
        "id_token" => "id123",
        "expiry_date" => "2024-12-31",
        "other_field" => "ignored"
      }.to_json

      credentials = @adapter.extract_credentials(content)

      assert_equal "access123", credentials["access_token"]
      assert_equal "refresh456", credentials["refresh_token"]
      assert_equal "email profile", credentials["scope"]
      assert_equal "Bearer", credentials["token_type"]
      assert_equal "id123", credentials["id_token"]
      assert_equal "2024-12-31", credentials["expiry_date"]
      refute credentials.key?("other_field")
    end

    test "generate_config returns credentials as-is" do
      credentials = { "refresh_token" => "refresh", "access_token" => "access" }

      config = @adapter.generate_config(credentials)

      assert_equal credentials, config
    end

    test "config_files returns oauth_creds and settings files" do
      credentials = { "refresh_token" => "refresh123" }

      files = @adapter.config_files(credentials)

      # OAuth creds file
      assert files.key?("/home/gemini/.gemini/oauth_creds.json")
      oauth = JSON.parse(files["/home/gemini/.gemini/oauth_creds.json"])
      assert_equal "refresh123", oauth["refresh_token"]

      # Settings file
      assert files.key?("/home/gemini/.gemini/settings.json")
      settings = JSON.parse(files["/home/gemini/.gemini/settings.json"])
      assert_equal "oauth-personal", settings.dig("security", "auth", "selectedType")
      assert_equal false, settings.dig("security", "folderTrust", "enabled")
      assert_equal "auto_edit", settings.dig("tools", "approvalMode")
      assert_equal true, settings.dig("tools", "autoAccept")
    end

    test "tmpfs_paths returns gemini directories" do
      paths = @adapter.tmpfs_paths

      assert_includes paths, "/home/gemini/.gemini"
      assert_includes paths, "/home/gemini/.mitmproxy"
    end

    test "required_env_fields returns google cloud project" do
      fields = @adapter.required_env_fields

      assert_equal 1, fields.size
      assert_equal "google_cloud_project", fields.first[:key]
      assert_equal true, fields.first[:required]
    end

    test "env_vars_from_metadata returns GOOGLE_CLOUD_PROJECT" do
      metadata = { "google_cloud_project" => "my-project-123" }

      env_vars = @adapter.env_vars_from_metadata(metadata)

      assert_equal "my-project-123", env_vars["GOOGLE_CLOUD_PROJECT"]
    end

    test "env_vars_from_metadata omits nil values" do
      metadata = { "google_cloud_project" => nil }

      env_vars = @adapter.env_vars_from_metadata(metadata)

      refute env_vars.key?("GOOGLE_CLOUD_PROJECT")
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
                      { "key" => "terminal_session_token", "value" => { "stringValue" => @session.route_token } }
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
  end
end
