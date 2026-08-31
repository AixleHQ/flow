# frozen_string_literal: true

require "test_helper"

module Agents
  class BaseAdapterTest < ActiveSupport::TestCase
    class TestAdapter < BaseAdapter
      def config_path
        "/home/user/.agent/config.json"
      end

      def home_dir
        "/home/user"
      end

      def auth_required_keys
        %w[api_key user_id]
      end

      def auth_complete?(config_content)
        config = parse_json(config_content)
        config["api_key"].present?
      end

      def extract_credentials(config_content)
        config = parse_json(config_content)
        { api_key: config["api_key"], user_id: config["user_id"] }
      end

      def generate_config(credentials, workflow_config = {})
        {
          "api_key" => credentials[:api_key],
          "user_id" => credentials[:user_id]
        }
      end
    end

    setup do
      @adapter = TestAdapter.new
    end

    # == Required Methods Tests ==

    test "config_path must be implemented" do
      base = BaseAdapter.new

      assert_raises(NotImplementedError) { base.config_path }
    end

    test "home_dir must be implemented" do
      base = BaseAdapter.new

      assert_raises(NotImplementedError) { base.home_dir }
    end

    test "auth_required_keys must be implemented" do
      base = BaseAdapter.new

      assert_raises(NotImplementedError) { base.auth_required_keys }
    end

    test "auth_complete? must be implemented" do
      base = BaseAdapter.new

      assert_raises(NotImplementedError) { base.auth_complete?("{}") }
    end

    test "extract_credentials must be implemented" do
      base = BaseAdapter.new

      assert_raises(NotImplementedError) { base.extract_credentials("{}") }
    end

    test "generate_config must be implemented" do
      base = BaseAdapter.new

      assert_raises(NotImplementedError) { base.generate_config({}) }
    end

    # == Default Implementations Tests ==

    test "auth_watch_path defaults to config_path" do
      assert_equal @adapter.config_path, @adapter.auth_watch_path
    end

    test "config_files returns path to content mapping" do
      credentials = { api_key: "test-key", user_id: "user-123" }

      files = @adapter.config_files(credentials)

      assert files.key?(@adapter.config_path)
      content = JSON.parse(files[@adapter.config_path])
      assert_equal "test-key", content["api_key"]
    end

    test "container_uid returns 1001" do
      assert_equal 1001, @adapter.container_uid
    end

    # == MCP STDIO Environment Tests ==

    test "mcp_stdio_env injects the baked Playwright browsers path (task #340)" do
      server = OpenStruct.new(env: {})

      assert_equal "/opt/playwright-browsers",
                   @adapter.mcp_stdio_env(server)["PLAYWRIGHT_BROWSERS_PATH"]
    end

    test "mcp_stdio_env injects the browsers path even when the server has no env" do
      server = OpenStruct.new(name: "playwright")

      assert_equal({ "PLAYWRIGHT_BROWSERS_PATH" => "/opt/playwright-browsers" },
                   @adapter.mcp_stdio_env(server))
    end

    test "mcp_stdio_env merges the server env on top of the baseline" do
      server = OpenStruct.new(env: { "KEY" => "v" })

      assert_equal({ "PLAYWRIGHT_BROWSERS_PATH" => "/opt/playwright-browsers", "KEY" => "v" },
                   @adapter.mcp_stdio_env(server))
    end

    test "mcp_stdio_env lets the server override the baseline browsers path" do
      server = OpenStruct.new(env: { "PLAYWRIGHT_BROWSERS_PATH" => "/custom/path" })

      assert_equal "/custom/path",
                   @adapter.mcp_stdio_env(server)["PLAYWRIGHT_BROWSERS_PATH"]
    end

    # == MCP STDIO Args Pinning Tests (task #340) ==

    test "mcp_stdio_args pins an unversioned @playwright/mcp spec to the baked version" do
      server = OpenStruct.new(args: [ "@playwright/mcp", "--headless" ])

      assert_equal [ "@playwright/mcp@#{BaseAdapter::PLAYWRIGHT_MCP_VERSION}", "--headless" ],
                   @adapter.mcp_stdio_args(server)
    end

    test "mcp_stdio_args re-pins a floating @playwright/mcp@latest to the baked version" do
      server = OpenStruct.new(args: [ "-y", "@playwright/mcp@latest" ])

      assert_equal [ "-y", "@playwright/mcp@#{BaseAdapter::PLAYWRIGHT_MCP_VERSION}" ],
                   @adapter.mcp_stdio_args(server)
    end

    test "mcp_stdio_args re-pins an @playwright/mcp spec already at a different version" do
      server = OpenStruct.new(args: [ "@playwright/mcp@0.0.1" ])

      assert_equal [ "@playwright/mcp@#{BaseAdapter::PLAYWRIGHT_MCP_VERSION}" ],
                   @adapter.mcp_stdio_args(server)
    end

    test "mcp_stdio_args never emits a bare, floatable @playwright/mcp spec" do
      server = OpenStruct.new(args: [ "@playwright/mcp" ])

      emitted = @adapter.mcp_stdio_args(server)
      refute_includes emitted, "@playwright/mcp",
                      "emitted command must not float independently of PLAYWRIGHT_MCP_VERSION"
      assert(emitted.all? { |a| a !~ %r{\A@playwright/mcp@latest\z} })
    end

    test "mcp_stdio_args leaves non-Playwright args untouched" do
      server = OpenStruct.new(args: [ "-y", "some-other-mcp", "--flag" ])

      assert_equal [ "-y", "some-other-mcp", "--flag" ], @adapter.mcp_stdio_args(server)
    end

    test "mcp_stdio_args returns an empty array when the server has no args" do
      assert_equal [], @adapter.mcp_stdio_args(OpenStruct.new(name: "remote"))
      assert_equal [], @adapter.mcp_stdio_args(OpenStruct.new(args: []))
    end

    # == Environment Variables Tests ==

    test "required_env_fields returns empty array by default" do
      base = BaseAdapter.new

      assert_equal [], base.required_env_fields
    end

    test "env_vars_from_metadata returns empty hash by default" do
      base = BaseAdapter.new

      assert_equal({}, base.env_vars_from_metadata({ "key" => "value" }))
    end

    test "validate_metadata returns errors for missing required fields" do
      adapter_with_fields = Class.new(BaseAdapter) do
        def required_env_fields
          [
            { key: "project_id", label: "Project ID", required: true },
            { key: "optional_field", label: "Optional", required: false }
          ]
        end
      end.new

      errors = adapter_with_fields.validate_metadata({})

      assert_includes errors, "Project ID is required"
      refute errors.any? { |e| e.include?("Optional") }
    end

    test "validate_metadata returns empty for valid metadata" do
      adapter_with_fields = Class.new(BaseAdapter) do
        def required_env_fields
          [ { key: "project_id", label: "Project ID", required: true } ]
        end
      end.new

      errors = adapter_with_fields.validate_metadata({ "project_id" => "my-project" })

      assert_empty errors
    end

    test "requires_env_fields? returns true when has required fields" do
      adapter_with_fields = Class.new(BaseAdapter) do
        def required_env_fields
          [ { key: "project_id", label: "Project ID", required: true } ]
        end
      end.new

      assert adapter_with_fields.requires_env_fields?
    end

    test "requires_env_fields? returns false when no required fields" do
      adapter_with_optional = Class.new(BaseAdapter) do
        def required_env_fields
          [ { key: "optional", label: "Optional", required: false } ]
        end
      end.new

      refute_predicate adapter_with_optional, :requires_env_fields?
    end

    test "requires_env_fields? returns false when empty" do
      base = BaseAdapter.new

      refute_predicate base, :requires_env_fields?
    end

    # == JSON Parsing Tests ==

    test "parse_json handles valid JSON" do
      content = '{"key": "value", "number": 42}'

      result = @adapter.send(:parse_json, content)

      assert_equal "value", result["key"]
      assert_equal 42, result["number"]
    end

    test "parse_json returns empty hash for invalid JSON" do
      content = "not valid json {{"

      result = @adapter.send(:parse_json, content)

      assert_equal({}, result)
    end

    test "parse_json returns empty hash for empty string" do
      result = @adapter.send(:parse_json, "")

      assert_equal({}, result)
    end

    # == Concrete Adapter Tests ==

    test "TestAdapter auth_complete? returns true when api_key present" do
      content = '{"api_key": "test-key"}'

      assert @adapter.auth_complete?(content)
    end

    test "TestAdapter auth_complete? returns false when api_key missing" do
      content = '{"user_id": "123"}'

      refute @adapter.auth_complete?(content)
    end

    test "TestAdapter extract_credentials returns structured data" do
      content = '{"api_key": "key-123", "user_id": "user-456"}'

      credentials = @adapter.extract_credentials(content)

      assert_equal "key-123", credentials[:api_key]
      assert_equal "user-456", credentials[:user_id]
    end

    # == Proactive Refresh Hook ==

    test "refresh! defaults to a not_needed no-op" do
      # Agents whose credentials carry no refreshable OAuth token never refresh.
      assert_equal({ status: :not_needed, detail: nil }, @adapter.refresh!(Object.new))
    end

    # == Retired Model Mapping ==

    test "migrate_model_id passes ids through for an agent with no retirements" do
      # An adapter that declares no RETIRED_MODEL_REPLACEMENTS must never rewrite a pin.
      assert_equal "some-vendor-model", @adapter.migrate_model_id("some-vendor-model")
      assert_nil @adapter.migrate_model_id(nil)
      assert_equal "", @adapter.migrate_model_id("")
    end

    # == Launch-time Credential Preflight ==

    test "credential_preflight defaults to a no-op" do
      # Most agents have no launch-time read-back to perform; AgentSessionStrategy
      # skips raising entirely when this returns nil.
      assert_nil @adapter.credential_preflight(Object.new, Object.new, "abc123")
    end
  end
end
