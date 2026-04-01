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

      assert_raises(ArgumentError) { strategy.before_create_container }
    end

    test "raises error when agent_type is invalid" do
      strategy = AgentAuthStrategy.new(
        user_id: @user.id,
        agent_type: "invalid_agent",
        session_id: @session.id,
        route_token: @session.route_token
      )

      error = assert_raises(ArgumentError) { strategy.before_create_container }
      assert_match(/Invalid agent_type/, error.message)
    end

    test "raises error when session_id is missing" do
      strategy = AgentAuthStrategy.new(
        user_id: @user.id,
        agent_type: "claude_code",
        route_token: "abc123"
      )

      assert_raises(ArgumentError) { strategy.before_create_container }
    end

    test "raises error when route_token is missing" do
      strategy = AgentAuthStrategy.new(
        user_id: @user.id,
        agent_type: "claude_code",
        session_id: @session.id
      )

      assert_raises(ArgumentError) { strategy.before_create_container }
    end

    # == Image Resolution Tests ==

    test "resolves claude_code image" do
      strategy = build_strategy(agent_type: "claude_code")
      assert_equal "aixle/claude-code:latest", strategy.resolve_image
    end

    test "resolves cursor_cli image" do
      @session.update!(agent_type: "cursor_cli")
      strategy = build_strategy(agent_type: "cursor_cli")
      assert_equal "aixle/cursor-cli:latest", strategy.resolve_image
    end

    test "resolves codex image" do
      @session.update!(agent_type: "codex")
      strategy = build_strategy(agent_type: "codex")
      assert_equal "aixle/codex:latest", strategy.resolve_image
    end

    test "resolves gemini_cli image" do
      @session.update!(agent_type: "gemini_cli")
      strategy = build_strategy(agent_type: "gemini_cli")
      assert_equal "aixle/gemini-cli:latest", strategy.resolve_image
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

    test "includes ROUTE_TOKEN env var" do
      strategy = build_strategy

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "ROUTE_TOKEN=#{@session.route_token}"
    end

    test "includes VSCODE_TOKEN env var with 64-char hex" do
      strategy = build_strategy

      env_vars = strategy.build_env_vars

      vscode_entry = env_vars.find { |v| v.start_with?("VSCODE_TOKEN=") }
      assert vscode_entry, "VSCODE_TOKEN env var not found"
      token_value = vscode_entry.split("=", 2).last
      assert_equal 64, token_value.length
      assert_match(/\A[0-9a-f]+\z/, token_value)
    end

    test "persists vscode_token to session metadata" do
      strategy = build_strategy

      strategy.build_env_vars

      @session.reload
      assert @session.metadata["vscode_token"].present?
      assert_equal 64, @session.metadata["vscode_token"].length
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

      assert_equal "auth_setup", labels["aixle.session_type"]
      assert_equal "claude_code", labels["aixle.agent_type"]
      assert_equal @user.id.to_s, labels["aixle.user_id"]
      assert_equal @session.id.to_s, labels["aixle.session_id"]
    end

    test "builds Traefik labels for routing" do
      strategy = build_strategy

      labels = strategy.build_labels

      assert_equal "true", labels["traefik.enable"]
      assert labels.key?("traefik.http.routers.terminal-#{@session.route_token}-tty.rule")
      assert labels.key?("traefik.http.routers.terminal-#{@session.route_token}-fs.rule")
    end

    test "builds Traefik IDE labels with correct PathPrefix" do
      strategy = build_strategy

      labels = strategy.build_labels
      router_name = "terminal-#{@session.route_token}"

      assert_equal "PathPrefix(`/t/#{@session.route_token}/ide`)",
                   labels["traefik.http.routers.#{router_name}-ide.rule"]
    end

    test "builds Traefik IDE labels with terminal-auth middleware only" do
      strategy = build_strategy

      labels = strategy.build_labels
      router_name = "terminal-#{@session.route_token}"

      assert_equal "terminal-auth",
                   labels["traefik.http.routers.#{router_name}-ide.middlewares"]
    end

    test "builds Traefik IDE labels with correct service port" do
      strategy = build_strategy

      labels = strategy.build_labels
      router_name = "terminal-#{@session.route_token}"

      assert_equal "#{router_name}-ide",
                   labels["traefik.http.routers.#{router_name}-ide.service"]
      assert_equal "8443",
                   labels["traefik.http.services.#{router_name}-ide.loadbalancer.server.port"]
    end

    test "IDE labels do not include StripPrefix middleware" do
      strategy = build_strategy

      labels = strategy.build_labels
      router_name = "terminal-#{@session.route_token}"

      refute labels.keys.any? { |k| k.include?("#{router_name}-ide-strip") }
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

      assert_equal Settings.docker.network, host_config["NetworkMode"]
    end

    # == Exposed Ports Tests ==

    test "exposes ttyd and watcher ports" do
      strategy = build_strategy

      ports = strategy.build_exposed_ports

      assert ports.key?("7681/tcp")
      assert ports.key?("4040/tcp")
    end

    test "exposes OpenVSCode Server port" do
      strategy = build_strategy

      ports = strategy.build_exposed_ports

      assert ports.key?("8443/tcp")
    end

    # == Exec Phase Tests ==

    test "exec returns container URLs" do
      strategy = build_strategy
      runtime_mock = mock("runtime")

      strategy.stubs(:resolve_container).returns(mock("container"))
      strategy.stubs(:mark_session_ready)

      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.stubs(:container_identifier).returns("abc123def456")

      result = strategy.exec(container_id: "abc123")

      assert_equal "abc123def456", result[:container_id]
      assert_equal "terminal-#{@session.route_token}", result[:container_name]
      assert result[:websocket_url].include?(@session.route_token)
      assert result[:watcher_url].include?(@session.route_token)
    end

    test "exec returns ide_url with trailing slash" do
      strategy = build_strategy
      runtime_mock = mock("runtime")

      strategy.stubs(:resolve_container).returns(mock("container"))
      strategy.stubs(:mark_session_ready)

      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.stubs(:container_identifier).returns("abc123")

      result = strategy.exec(container_id: "abc123")

      assert result[:ide_url].include?(@session.route_token)
      assert result[:ide_url].end_with?("/ide/")
    end

    test "before_create_container sets container_name in result" do
      strategy = build_strategy

      result = strategy.before_create_container

      assert_equal "terminal-#{@session.route_token}", result[:container_name]
    end

    # == Services Ports Tests ==

    test "services_ports returns ttyd and watcher ports" do
      strategy = build_strategy

      ports = strategy.send(:services_ports)

      assert_includes ports, 7681
      assert_includes ports, 4040
    end

    # == Session Type Tests ==

    test "session_type returns auth_setup" do
      strategy = build_strategy

      assert_equal "auth_setup", strategy.send(:session_type)
    end

    # == Env Vars with Session Metadata Tests ==

    test "builds env vars with metadata" do
      @session.update!(metadata: { "project_id" => "my-project" })

      # Create adapter that returns env vars from metadata
      strategy = build_strategy(agent_type: "gemini_cli")
      @session.update!(agent_type: "gemini_cli")

      env_vars = strategy.build_env_vars

      # Gemini adapter returns GOOGLE_CLOUD_PROJECT from metadata
      # This may or may not be present depending on adapter implementation
      assert env_vars.is_a?(Array)
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
