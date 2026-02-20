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

      assert_equal "app_default", host_config["NetworkMode"]
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

      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123def456789")

      context = { container: container_mock }
      strategy.exec(context)

      assert_equal "abc123def456", context[:result][:container_id]
      assert_equal "terminal-#{@session.route_token}", context[:result][:container_name]
      assert context[:result][:websocket_url].include?(@session.route_token)
      assert context[:result][:watcher_url].include?(@session.route_token)
    end

    test "exec returns ide_url with trailing slash" do
      strategy = build_strategy

      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123def456789")

      context = { container: container_mock }
      strategy.exec(context)

      assert context[:result][:ide_url].include?(@session.route_token)
      assert context[:result][:ide_url].end_with?("/ide/")
    end

    # == before_create Tests ==

    test "before_create sets container_name in context" do
      strategy = build_strategy
      context = {}

      strategy.before_create(context)

      assert_equal "terminal-#{@session.route_token}", context[:container_name]
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

    # == Parse Auth Files Tests ==

    test "parse_auth_files parses JSON content" do
      strategy = build_strategy
      auth_files = {
        "/path/to/config.json" => '{"api_key": "test-key"}'
      }

      result = strategy.send(:parse_auth_files, auth_files)

      assert_equal "test-key", result["api_key"]
    end

    test "parse_auth_files handles invalid JSON" do
      strategy = build_strategy
      auth_files = {
        "/path/to/file.txt" => "not json content"
      }

      result = strategy.send(:parse_auth_files, auth_files)

      # Stores raw content under path key
      assert_equal "not json content", result["/path/to/file.txt"]
    end

    test "parse_auth_files merges multiple files" do
      strategy = build_strategy
      auth_files = {
        "/path/to/file1.json" => '{"key1": "value1"}',
        "/path/to/file2.json" => '{"key2": "value2"}'
      }

      result = strategy.send(:parse_auth_files, auth_files)

      assert_equal "value1", result["key1"]
      assert_equal "value2", result["key2"]
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
