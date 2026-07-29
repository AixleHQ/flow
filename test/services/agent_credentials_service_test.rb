# frozen_string_literal: true

require "test_helper"

class AgentCredentialsServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)

    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
    Rails.logger.stubs(:error)
  end

  # == Initialization Tests ==

  test "initializes with claude_code adapter" do
    service = AgentCredentialsService.new("claude_code")

    assert_equal "claude_code", service.agent_type
    assert_instance_of Agents::ClaudeCodeAdapter, service.adapter
  end

  test "initializes with cursor_cli adapter" do
    service = AgentCredentialsService.new("cursor_cli")

    assert_equal "cursor_cli", service.agent_type
    assert_instance_of Agents::CursorCliAdapter, service.adapter
  end

  test "initializes with gemini_cli adapter" do
    service = AgentCredentialsService.new("gemini_cli")

    assert_equal "gemini_cli", service.agent_type
    assert_instance_of Agents::GeminiCliAdapter, service.adapter
  end

  test "raises error for unknown agent type" do
    assert_raises(ArgumentError) do
      AgentCredentialsService.new("unknown_agent")
    end
  end

  # == Class Methods ==

  test "for creates service instance" do
    service = AgentCredentialsService.for("claude_code")

    assert_instance_of AgentCredentialsService, service
    assert_equal "claude_code", service.agent_type
  end

  test "supported_agents returns all adapter keys" do
    agents = AgentCredentialsService.supported_agents

    assert_includes agents, "claude_code"
    assert_includes agents, "cursor_cli"
    assert_includes agents, "gemini_cli"
    assert_includes agents, "codex"
  end

  test "supported? returns true for known agent" do
    assert AgentCredentialsService.supported?("claude_code")
    assert AgentCredentialsService.supported?("cursor_cli")
  end

  test "supported? returns false for unknown agent" do
    refute AgentCredentialsService.supported?("unknown")
  end

  # == Delegate Methods ==

  test "delegates config_path to adapter" do
    service = AgentCredentialsService.new("claude_code")

    assert_kind_of String, service.config_path
    assert_includes service.config_path, ".claude"
  end

  test "delegates home_dir to adapter" do
    service = AgentCredentialsService.new("claude_code")

    assert_kind_of String, service.home_dir
  end

  # == Extract from Container Tests ==

  test "extract_from_container returns credentials from container" do
    service = AgentCredentialsService.new("claude_code")

    runtime_mock = mock("runtime")
    service.instance_variable_set(:@runtime, runtime_mock)

    config_content = JSON.generate({
      "primaryApiKey" => "sk-ant-123",
      "lastAccountId" => "user_123"
    })
    runtime_mock.expects(:exec).with("container123", [ "cat", service.config_path ])
      .returns([ [ config_content ], [], 0 ])

    credentials = service.extract_from_container("container123")

    assert_kind_of Hash, credentials
    assert credentials[:api_key].present? || credentials["primaryApiKey"].present?
  end

  test "extract_from_container returns empty hash when file not found" do
    service = AgentCredentialsService.new("claude_code")

    runtime_mock = mock("runtime")
    service.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:exec).returns([ [], [ "No such file" ], 1 ])

    credentials = service.extract_from_container("container123")

    assert_equal({}, credentials)
  end

  test "extract_from_container returns empty hash when container not found" do
    service = AgentCredentialsService.new("claude_code")

    runtime_mock = mock("runtime")
    service.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:exec).raises(StandardError.new("container not found"))

    credentials = service.extract_from_container("missing123")

    assert_equal({}, credentials)
  end

  # == Auth Complete in Container Tests ==

  test "auth_complete_in_container? returns true when credentials present" do
    service = AgentCredentialsService.new("claude_code")

    runtime_mock = mock("runtime")
    service.instance_variable_set(:@runtime, runtime_mock)

    config_content = JSON.generate({
      "primaryApiKey" => "sk-ant-123",
      "lastAccountId" => "user_123"
    })
    runtime_mock.expects(:exec).returns([ [ config_content ], [], 0 ])

    assert service.auth_complete_in_container?("container123")
  end

  test "auth_complete_in_container? returns false when file not found" do
    service = AgentCredentialsService.new("claude_code")

    runtime_mock = mock("runtime")
    service.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:exec).returns([ [], [], 1 ])

    refute service.auth_complete_in_container?("container123")
  end

  # == Write to Container Tests ==

  test "write_to_container writes config files" do
    service = AgentCredentialsService.new("claude_code")

    runtime_mock = mock("runtime")
    service.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:write_file).at_least_once.returns(true)

    credentials = { api_key: "test-key", account_id: "user-123" }

    service.write_to_container("container123", credentials)
  end

  test "write_to_container raises on runtime error" do
    service = AgentCredentialsService.new("claude_code")

    runtime_mock = mock("runtime")
    service.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:write_file).raises(StandardError.new("Write failed"))

    assert_raises(StandardError) do
      service.write_to_container("container123", { api_key: "test" })
    end
  end

  # == Save Credentials from Container Tests ==

  test "save_credentials_from_container creates agent credential" do
    service = AgentCredentialsService.new("claude_code")

    runtime_mock = mock("runtime")
    service.instance_variable_set(:@runtime, runtime_mock)

    config_content = JSON.generate({
      "primaryApiKey" => "sk-ant-123",
      "lastAccountId" => "user_123"
    })
    runtime_mock.expects(:exec).returns([ [ config_content ], [], 0 ])

    credential = service.save_credentials_from_container(@user, @user.company_memberships.first&.company, "container123")

    assert_instance_of AgentCredential, credential
    assert_equal "claude_code", credential.agent_type
    assert_equal @user.id, credential.user_id
  end

  test "save_credentials_from_container raises when no credentials" do
    service = AgentCredentialsService.new("claude_code")

    runtime_mock = mock("runtime")
    service.instance_variable_set(:@runtime, runtime_mock)

    runtime_mock.expects(:exec).returns([ [], [], 1 ])

    assert_raises(RuntimeError, "No credentials found in container") do
      service.save_credentials_from_container(@user, @user.company_memberships.first&.company, "container123")
    end
  end

  # == Load Credentials to Container Tests ==

  test "load_credentials_to_container writes existing credentials" do
    service = AgentCredentialsService.new("claude_code")

    runtime_mock = mock("runtime")
    service.instance_variable_set(:@runtime, runtime_mock)

    credential = create(:agent_credential,
      user: @user,
      agent_type: "claude_code",
      config_data: { api_key: "existing-key", account_id: "user-123" }
    )

    runtime_mock.stubs(:write_file).returns(true)

    service.load_credentials_to_container(@user, "container123")

    credential.reload
    assert credential.last_used_at.present?
  end

  test "load_credentials_to_container raises when no credentials exist" do
    service = AgentCredentialsService.new("claude_code")

    assert_raises(RuntimeError, "No credentials found for claude_code") do
      service.load_credentials_to_container(@user, "container123")
    end
  end
end
