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
  end
end
