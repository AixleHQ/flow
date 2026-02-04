# frozen_string_literal: true

require "test_helper"

module ContainerStrategies
  class AgentAuthStrategyTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @session = create(:terminal_session, user: @user, agent_type: "claude_code")

      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)
    end

    # == Validation Tests ==

    test "raises error when user_id is missing" do
      strategy = AgentAuthStrategy.new(
        agent_type: "claude_code",
        session_id: @session.id,
        route_token: @session.route_token
      )

      assert_raises(ArgumentError) { strategy.before_create({}) }
    end

    test "raises error when agent_type is invalid" do
      strategy = AgentAuthStrategy.new(
        user_id: @user.id,
        agent_type: "invalid_agent",
        session_id: @session.id,
        route_token: @session.route_token
      )

      error = assert_raises(ArgumentError) { strategy.before_create({}) }
      assert_match(/Invalid agent_type/, error.message)
    end

    test "raises error when session_id is missing" do
      strategy = AgentAuthStrategy.new(
        user_id: @user.id,
        agent_type: "claude_code",
        route_token: "abc123"
      )

      assert_raises(ArgumentError) { strategy.before_create({}) }
    end

    test "raises error when route_token is missing" do
      strategy = AgentAuthStrategy.new(
        user_id: @user.id,
        agent_type: "claude_code",
        session_id: @session.id
      )

      assert_raises(ArgumentError) { strategy.before_create({}) }
    end

    # == Image Resolution Tests ==

    test "resolves claude_code image" do
      strategy = build_strategy(agent_type: "claude_code")
      assert_equal "palad/claude-code:latest", strategy.resolve_image
    end

    test "resolves cursor_cli image" do
      @session.update!(agent_type: "cursor_cli")
      strategy = build_strategy(agent_type: "cursor_cli")
      assert_equal "palad/cursor-cli:latest", strategy.resolve_image
    end

    test "resolves codex image" do
      @session.update!(agent_type: "codex")
      strategy = build_strategy(agent_type: "codex")
      assert_equal "palad/codex:latest", strategy.resolve_image
    end

    test "resolves gemini_cli image" do
      @session.update!(agent_type: "gemini_cli")
      strategy = build_strategy(agent_type: "gemini_cli")
      assert_equal "palad/gemini-cli:latest", strategy.resolve_image
    end

    # == Environment Variables Tests ==

    test "builds env vars with session info" do
      strategy = build_strategy

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "USER_ID=#{@user.id}"
      assert_includes env_vars, "AGENT_TYPE=claude_code"
      assert_includes env_vars, "SESSION_TYPE=auth_setup"
      assert_includes env_vars, "SESSION_ID=#{@session.id}"
      assert_includes env_vars, "TTYD_PORT=7681"
      assert_includes env_vars, "WATCHER_PORT=4040"
    end

    test "builds env vars with agent-specific paths" do
      strategy = build_strategy

      env_vars = strategy.build_env_vars

      # Claude Code uses /home/coder
      assert env_vars.any? { |v| v.start_with?("HOME_DIR=") }
      assert env_vars.any? { |v| v.start_with?("AUTH_WATCH_PATH=") }
      assert env_vars.any? { |v| v.start_with?("AUTH_REQUIRED_KEYS=") }
    end

    test "includes TTYD_CMD for auth" do
      strategy = build_strategy(agent_type: "claude_code")

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "TTYD_CMD=claude"
    end

    test "cursor_cli auth uses login command" do
      @session.update!(agent_type: "cursor_cli")
      strategy = build_strategy(agent_type: "cursor_cli")

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "TTYD_CMD=agent login"
    end

    # == Labels Tests ==

    test "builds labels with session info" do
      strategy = build_strategy

      labels = strategy.build_labels

      assert_equal "auth_setup", labels["palad.session_type"]
      assert_equal "claude_code", labels["palad.agent_type"]
      assert_equal @user.id.to_s, labels["palad.user_id"]
      assert_equal @session.id.to_s, labels["palad.session_id"]
    end

    test "builds Traefik labels for routing" do
      strategy = build_strategy

      labels = strategy.build_labels

      assert_equal "true", labels["traefik.enable"]
      assert labels.key?("traefik.http.routers.terminal-#{@session.route_token}-tty.rule")
      assert labels.key?("traefik.http.routers.terminal-#{@session.route_token}-fs.rule")
    end

    # == Host Config Tests ==

    test "builds host config with tmpfs mounts" do
      strategy = build_strategy

      host_config = strategy.build_host_config

      assert host_config.key?("Tmpfs")
      assert host_config["Tmpfs"].is_a?(Hash)
    end

    test "builds host config with network mode" do
      strategy = build_strategy

      host_config = strategy.build_host_config

      assert_equal "app_default", host_config["NetworkMode"]
    end

    # == Exposed Ports Tests ==

    test "exposes ttyd and watcher ports" do
      strategy = build_strategy

      ports = strategy.build_exposed_ports

      assert ports.key?("7681/tcp")
      assert ports.key?("4040/tcp")
    end

    # == Exec Phase Tests ==

    test "exec returns container URLs" do
      strategy = build_strategy

      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123def456789")

      context = { container: container_mock }
      strategy.exec(context)

      assert_equal "abc123def456", context[:result][:container_id]
      assert_equal "terminal-#{@session.route_token}", context[:result][:container_name]
      assert context[:result][:websocket_url].include?(@session.route_token)
      assert context[:result][:watcher_url].include?(@session.route_token)
    end

    # == before_create Tests ==

    test "before_create sets container_name in context" do
      strategy = build_strategy
      context = {}

      strategy.before_create(context)

      assert_equal "terminal-#{@session.route_token}", context[:container_name]
    end

    private

    def build_strategy(agent_type: "claude_code")
      AgentAuthStrategy.new(
        user_id: @user.id,
        agent_type: agent_type,
        session_id: @session.id,
        route_token: @session.route_token
      )
    end
  end
end
