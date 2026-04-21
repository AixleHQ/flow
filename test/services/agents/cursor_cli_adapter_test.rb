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
      assert cli_config["permissions"]["allow"].include?("Shell(git)")
      assert cli_config["permissions"]["deny"].include?("Shell(sudo)")

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
  end
end
