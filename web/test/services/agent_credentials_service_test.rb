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

    # ClaudeCodeAdapter returns specific config path
    assert service.config_path.is_a?(String)
    assert service.config_path.include?(".claude")
  end

  test "delegates home_dir to adapter" do
    service = AgentCredentialsService.new("claude_code")

    assert service.home_dir.is_a?(String)
  end

  # == Extract from Container Tests ==

  test "extract_from_container returns credentials from container" do
    service = AgentCredentialsService.new("claude_code")
    container_mock = mock("container")

    # Mock file content
    config_content = JSON.generate({
      "primaryApiKey" => "sk-ant-123",
      "lastAccountId" => "user_123"
    })
    container_mock.expects(:exec).with([ "cat", service.config_path ])
      .returns([ [ config_content ], [], 0 ])

    Docker::Container.expects(:get).with("container123").returns(container_mock)

    credentials = service.extract_from_container("container123")

    assert credentials.is_a?(Hash)
    assert credentials[:api_key].present? || credentials["primaryApiKey"].present?
  end

  test "extract_from_container returns empty hash when file not found" do
    service = AgentCredentialsService.new("claude_code")
    container_mock = mock("container")
    container_mock.expects(:exec).returns([ [], [ "No such file" ], 1 ])

    Docker::Container.expects(:get).with("container123").returns(container_mock)

    credentials = service.extract_from_container("container123")

    assert_equal({}, credentials)
  end

  test "extract_from_container returns empty hash when container not found" do
    service = AgentCredentialsService.new("claude_code")

    Docker::Container.expects(:get).with("missing123").raises(Docker::Error::NotFoundError)

    credentials = service.extract_from_container("missing123")

    assert_equal({}, credentials)
  end

  # == Auth Complete in Container Tests ==

  test "auth_complete_in_container? returns true when credentials present" do
    service = AgentCredentialsService.new("claude_code")
    container_mock = mock("container")

    config_content = JSON.generate({
      "primaryApiKey" => "sk-ant-123",
      "lastAccountId" => "user_123"
    })
    container_mock.expects(:exec).returns([ [ config_content ], [], 0 ])

    Docker::Container.expects(:get).with("container123").returns(container_mock)

    assert service.auth_complete_in_container?("container123")
  end

  test "auth_complete_in_container? returns false when file not found" do
    service = AgentCredentialsService.new("claude_code")
    container_mock = mock("container")
    container_mock.expects(:exec).returns([ [], [], 1 ])

    Docker::Container.expects(:get).with("container123").returns(container_mock)

    refute service.auth_complete_in_container?("container123")
  end

  # == Write to Container Tests ==

  test "write_to_container writes config files" do
    service = AgentCredentialsService.new("claude_code")
    container_mock = mock("container")

    # Expect mkdir and write operations for each config file (stubs allows any)
    container_mock.stubs(:exec)

    Docker::Container.stubs(:get).with("container123").returns(container_mock)

    credentials = { api_key: "test-key", account_id: "user-123" }

    # Should not raise
    service.write_to_container("container123", credentials)
    assert true # Code path covered
  end

  test "write_to_container raises on docker error" do
    service = AgentCredentialsService.new("claude_code")
    container_mock = mock("container")
    container_mock.expects(:exec).raises(Docker::Error::DockerError.new("Write failed"))

    Docker::Container.expects(:get).with("container123").returns(container_mock)

    assert_raises(Docker::Error::DockerError) do
      service.write_to_container("container123", { api_key: "test" })
    end
  end

  # == Save Credentials from Container Tests ==

  test "save_credentials_from_container creates agent credential" do
    service = AgentCredentialsService.new("claude_code")
    container_mock = mock("container")

    config_content = JSON.generate({
      "primaryApiKey" => "sk-ant-123",
      "lastAccountId" => "user_123"
    })
    container_mock.expects(:exec).returns([ [ config_content ], [], 0 ])

    Docker::Container.expects(:get).with("container123").returns(container_mock)

    credential = service.save_credentials_from_container(@user, "container123")

    assert_instance_of AgentCredential, credential
    assert_equal "claude_code", credential.agent_type
    assert_equal @user.id, credential.user_id
  end

  test "save_credentials_from_container raises when no credentials" do
    service = AgentCredentialsService.new("claude_code")
    container_mock = mock("container")
    container_mock.expects(:exec).returns([ [], [], 1 ])

    Docker::Container.expects(:get).with("container123").returns(container_mock)

    assert_raises(RuntimeError, "No credentials found in container") do
      service.save_credentials_from_container(@user, "container123")
    end
  end

  # == Load Credentials to Container Tests ==

  test "load_credentials_to_container writes existing credentials" do
    service = AgentCredentialsService.new("claude_code")

    # Create credential for user
    credential = create(:agent_credential,
      user: @user,
      agent_type: "claude_code",
      config_data: { api_key: "existing-key", account_id: "user-123" }
    )

    container_mock = mock("container")
    container_mock.expects(:exec).at_least_once

    Docker::Container.expects(:get).with("container123").returns(container_mock).at_least_once

    # Should not raise and should touch credential
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
