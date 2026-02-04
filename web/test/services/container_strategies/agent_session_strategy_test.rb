# frozen_string_literal: true

require "test_helper"

module ContainerStrategies
  class AgentSessionStrategyTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @session = create(:terminal_session, user: @user, agent_type: "claude_code")
      @credential = create(:agent_credential, user: @user, agent_type: "claude_code")

      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)
    end

    # == Inheritance Tests ==

    test "inherits from AgentAuthStrategy" do
      assert AgentSessionStrategy < AgentAuthStrategy
    end

    # == Environment Variables Tests ==

    test "builds env vars with agent_session type" do
      strategy = build_strategy

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "SESSION_TYPE=agent_session"
      refute env_vars.any? { |v| v == "SESSION_TYPE=auth_setup" }
    end

    test "builds env vars with MCP configuration" do
      strategy = build_strategy

      env_vars = strategy.build_env_vars

      assert env_vars.any? { |v| v.start_with?("MCP_SERVER_URL=") }
      assert env_vars.any? { |v| v.start_with?("MCP_SESSION_KEY=") }
    end

    test "uses session command instead of auth command" do
      strategy = build_strategy(agent_type: "claude_code")

      env_vars = strategy.build_env_vars

      # Session command for claude_code is "claude"
      assert_includes env_vars, "TTYD_CMD=claude"
    end

    test "cursor_cli session uses agent command" do
      @session.update!(agent_type: "cursor_cli")
      @credential.update!(agent_type: "cursor_cli")
      strategy = build_strategy(agent_type: "cursor_cli")

      env_vars = strategy.build_env_vars

      # Session command for cursor_cli is "agent" (not "agent login")
      assert_includes env_vars, "TTYD_CMD=agent"
    end

    test "codex session uses yolo flag" do
      @session.update!(agent_type: "codex")
      @credential.update!(agent_type: "codex")
      strategy = build_strategy(agent_type: "codex")

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "TTYD_CMD=codex --yolo"
    end

    # == Labels Tests ==

    test "builds labels with agent_session type" do
      strategy = build_strategy

      labels = strategy.build_labels

      assert_equal "agent_session", labels["palad.session_type"]
    end

    # == before_exec Tests ==

    test "before_exec loads credentials into container" do
      strategy = build_strategy

      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123def456789")

      # Expect credential.write_to_container to be called
      @credential.expects(:write_to_container).with("abc123def456")

      context = { container: container_mock }
      strategy.before_exec(context)
    end

    test "before_exec skips when no credential" do
      # Create strategy without credential
      strategy = AgentSessionStrategy.new(
        user_id: @user.id,
        agent_type: "claude_code",
        session_id: @session.id,
        route_token: @session.route_token,
        credential: nil
      )

      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123def456789")

      # write_to_container should NOT be called (no expects)
      context = { container: container_mock }
      strategy.before_exec(context)

      # Test passes if no error - credential was nil so no write attempted
      assert true
    end

    # == before_cleanup Tests ==

    test "before_cleanup sets artifacts in result" do
      strategy = build_strategy

      container_mock = mock("container")
      # Mock read_file_from_container to return nil (no files found)
      strategy.stubs(:read_file_from_container).returns(nil)

      context = { container: container_mock, result: {} }
      strategy.before_cleanup(context)

      assert context[:result].key?(:artifacts)
      assert context[:result].key?(:artifacts_count)
    end

    # == Full Flow Tests ==

    test "session_type returns agent_session" do
      strategy = build_strategy

      assert_equal "agent_session", strategy.send(:session_type)
    end

    private

    def build_strategy(agent_type: "claude_code", credential: nil)
      cred = credential.nil? ? @credential : credential
      AgentSessionStrategy.new(
        user_id: @user.id,
        agent_type: agent_type,
        session_id: @session.id,
        route_token: @session.route_token,
        credential: cred
      )
    end
  end
end
