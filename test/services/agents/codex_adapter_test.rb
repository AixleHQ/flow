# frozen_string_literal: true

require "test_helper"

module Agents
  class CodexAdapterTest < ActiveSupport::TestCase
    setup do
      @adapter = CodexAdapter.new
    end

    test "config_path returns codex auth.json path" do
      assert_equal "/home/codex/.codex/auth.json", @adapter.config_path
    end

    test "home_dir returns codex home" do
      assert_equal "/home/codex", @adapter.home_dir
    end

    test "auth_required_keys returns tokens" do
      assert_equal %w[tokens], @adapter.auth_required_keys
    end

    test "auth_complete? returns true with access_token" do
      content = { "tokens" => { "access_token" => "abc123" } }.to_json
      assert @adapter.auth_complete?(content)
    end

    test "auth_complete? returns true with refresh_token" do
      content = { "tokens" => { "refresh_token" => "refresh123" } }.to_json
      assert @adapter.auth_complete?(content)
    end

    test "auth_complete? returns false without tokens" do
      content = {}.to_json
      refute @adapter.auth_complete?(content)
    end

    test "auth_complete? returns false when tokens is not a hash" do
      content = { "tokens" => "invalid" }.to_json
      refute @adapter.auth_complete?(content)
    end

    test "extract_credentials extracts relevant fields" do
      content = {
        "tokens" => { "access_token" => "abc" },
        "OPENAI_API_KEY" => "sk-123",
        "account_id" => "acc-456",
        "last_refresh" => "2024-01-01",
        "other_field" => "ignored"
      }.to_json

      credentials = @adapter.extract_credentials(content)

      assert_equal({ "access_token" => "abc" }, credentials["tokens"])
      assert_equal "sk-123", credentials["OPENAI_API_KEY"]
      assert_equal "acc-456", credentials["account_id"]
      assert_equal "2024-01-01", credentials["last_refresh"]
      refute credentials.key?("other_field")
    end

    test "generate_config returns credentials with last_refresh" do
      credentials = { "tokens" => { "access_token" => "abc" } }

      config = @adapter.generate_config(credentials)

      assert_equal({ "access_token" => "abc" }, config["tokens"])
      assert config["last_refresh"].present?
    end

    test "generate_config preserves existing last_refresh" do
      credentials = { "last_refresh" => "2024-01-01" }

      config = @adapter.generate_config(credentials)

      assert_equal "2024-01-01", config["last_refresh"]
    end

    test "config_files returns auth.json and config.toml" do
      credentials = { "tokens" => { "access_token" => "abc" } }

      files = @adapter.config_files(credentials, { workspace: "/project" })

      assert files.key?("/home/codex/.codex/auth.json")
      assert files.key?("/home/codex/.codex/config.toml")

      # Check auth.json content
      auth = JSON.parse(files["/home/codex/.codex/auth.json"])
      assert_equal({ "access_token" => "abc" }, auth["tokens"])

      # Check config.toml content
      toml = files["/home/codex/.codex/config.toml"]
      assert_includes toml, 'model = "gpt-5.3-codex"'
      assert_includes toml, 'approval_policy = "never"'
      assert_includes toml, 'sandbox_mode = "danger-full-access"'
      assert_includes toml, 'trust_level = "trusted"'
      assert_includes toml, "/project"
    end

    test "config_files uses default workspace when not provided" do
      credentials = {}
      files = @adapter.config_files(credentials)

      toml = files["/home/codex/.codex/config.toml"]
      assert_includes toml, "/workspace"
    end

    test "session_command returns codex exec with explicit model for non_interactive mode" do
      result = @adapter.session_command(mode: "non_interactive", prompt: "Run tests")

      assert_equal "codex exec --skip-git-repo-check --model gpt-5.3-codex", result
    end
  end
end
