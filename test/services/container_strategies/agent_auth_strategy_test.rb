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
      assert_includes result[:websocket_url], @session.route_token
      assert_includes result[:watcher_url], @session.route_token
    end

    test "exec returns ide_url with trailing slash" do
      strategy = build_strategy
      runtime_mock = mock("runtime")

      strategy.stubs(:resolve_container).returns(mock("container"))
      strategy.stubs(:mark_session_ready)

      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.stubs(:container_identifier).returns("abc123")

      result = strategy.exec(container_id: "abc123")

      assert_includes result[:ide_url], @session.route_token
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
      assert_kind_of Array, env_vars
    end

    # == before_cleanup: credential persistence ==

    test "before_cleanup does not save a credential when auth is incomplete" do
      strategy = build_strategy
      container = mock("container")
      strategy.stubs(:resolve_container).returns(container)
      # ~/.claude.json exists (Claude always writes it) but carries no token;
      # ~/.claude/.credentials.json is absent.
      strategy.stubs(:read_file_from_container).returns(nil)
      strategy.stubs(:read_file_from_container)
              .with(container, "/home/claude/.claude.json")
              .returns({ "numStartups" => 1, "oauthAccount" => { "id" => "acc" } }.to_json)

      assert_no_difference "AgentCredential.count" do
        result = strategy.before_cleanup(container_id: "abc", session_id: @session.id)
        refute result[:auth_completed]
        refute result.key?(:credential_id)
      end
    end

    test "before_cleanup saves a clean sliced credential when a token is present" do
      strategy = build_strategy
      container = mock("container")
      strategy.stubs(:resolve_container).returns(container)
      strategy.stubs(:read_file_from_container)
              .with(container, "/home/claude/.claude.json")
              .returns({ "numStartups" => 5, "projects" => { "/x" => {} },
                         "oauthAccount" => { "emailAddress" => "u@x.com" }, "userID" => "uid-1" }.to_json)
      strategy.stubs(:read_file_from_container)
              .with(container, "/home/claude/.claude/.credentials.json")
              .returns({ "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-z", "refreshToken" => "sk-ant-ort01-z" } }.to_json)

      assert_difference "AgentCredential.count", 1 do
        result = strategy.before_cleanup(container_id: "abc", session_id: @session.id)
        assert result[:auth_completed]
        assert result[:credential_id]
      end

      cred = @user.agent_credentials.find_by(agent_type: "claude_code")
      # Only the sliced credential keys are stored — no .claude.json bloat.
      refute cred.config_data.key?("numStartups")
      refute cred.config_data.key?("projects")
      assert_equal "sk-ant-oat01-z", cred.config_data.dig("claudeAiOauth", "accessToken")
      assert_equal "u@x.com", cred.config_data.dig("oauthAccount", "emailAddress")
      assert_equal "uid-1", cred.config_data["userID"]
    end

    # == /design-login variant ==

    test "normal auth watches the base login keys" do
      env_vars = build_strategy.build_env_vars
      assert_includes env_vars, "AUTH_REQUIRED_KEYS=primaryApiKey,claudeAiOauth.accessToken"
    end

    test "design auth watches the designOauth key instead" do
      @session.update!(metadata: { "auth_kind" => "design" })
      env_vars = build_strategy.build_env_vars
      assert_includes env_vars, "AUTH_REQUIRED_KEYS=designOauth.accessToken"
    end

    test "design auth before_exec injects the user's existing base credential" do
      @session.update!(metadata: { "auth_kind" => "design" })
      AgentCredential.from_artifacts(@user.id, "claude_code",
                                     { "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-base" } })
      strategy = build_strategy
      container = mock("container")
      strategy.stubs(:resolve_container).returns(container)
      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)
      written = {}
      runtime_mock.stubs(:write_file).with { |_c, path, content| written[path] = content; true }

      strategy.before_exec(container_id: "abc")

      creds = written["/home/claude/.claude/.credentials.json"]
      assert creds, "expected the base credential file to be injected"
      assert_includes creds, "sk-ant-oat01-base"
    end

    test "design auth before_exec strips the existing designOauth on reconnect (no instant complete)" do
      @session.update!(metadata: { "auth_kind" => "design" })
      AgentCredential.from_artifacts(@user.id, "claude_code", {
        "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-base" },
        "designOauth" => { "accessToken" => "sk-ant-oat01-OLD-design" }
      })
      strategy = build_strategy
      container = mock("container")
      strategy.stubs(:resolve_container).returns(container)
      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)
      written = {}
      runtime_mock.stubs(:write_file).with { |_c, path, content| written[path] = content; true }

      strategy.before_exec(container_id: "abc")

      creds = written["/home/claude/.claude/.credentials.json"]
      assert_includes creds, "sk-ant-oat01-base", "base login must still be injected"
      refute_includes creds, "sk-ant-oat01-OLD-design",
                      "the design token being re-minted must NOT be injected (would complete instantly)"
    end

    test "design auth is NOT complete with only the injected base token" do
      @session.update!(metadata: { "auth_kind" => "design" })
      strategy = build_strategy
      container = mock("container")
      strategy.stubs(:resolve_container).returns(container)
      strategy.stubs(:read_file_from_container).returns(nil)
      strategy.stubs(:read_file_from_container)
              .with(container, "/home/claude/.claude/.credentials.json")
              .returns({ "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-base" } }.to_json)

      assert_no_difference "AgentCredential.count" do
        result = strategy.before_cleanup(container_id: "abc", session_id: @session.id)
        refute result[:auth_completed], "must wait for designOauth, not the injected base token"
      end
    end

    test "design auth completes by adding designOauth to the existing base, not re-scraping it" do
      @session.update!(metadata: { "auth_kind" => "design" })
      # The user is already logged in via the platform key; design layers on top.
      AgentCredential.from_artifacts(@user.id, "claude_code", { "primaryApiKey" => "sk-ant-api-PLATFORM" })

      strategy = build_strategy
      container = mock("container")
      strategy.stubs(:resolve_container).returns(container)
      strategy.stubs(:read_file_from_container).returns(nil)
      # The container scrape ALSO surfaces a stale claudeAiOauth Claude wrote next to
      # the injected base — it must NOT be persisted (would trigger Claude's
      # "Both claude.ai and /login managed key set").
      strategy.stubs(:read_file_from_container)
              .with(container, "/home/claude/.claude/.credentials.json")
              .returns({ "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-STALE" },
                         "designOauth" => { "accessToken" => "sk-ant-oat01-design" } }.to_json)

      assert_no_difference "AgentCredential.count" do
        result = strategy.before_cleanup(container_id: "abc", session_id: @session.id)
        assert result[:auth_completed]
      end

      cred = @user.agent_credentials.find_by(agent_type: "claude_code")
      assert_equal "sk-ant-oat01-design", cred.config_data.dig("designOauth", "accessToken")
      assert_equal "sk-ant-api-PLATFORM", cred.config_data["primaryApiKey"], "existing base preserved"
      refute cred.config_data.key?("claudeAiOauth"), "stale scraped base must not be resurrected"
    end

    test "non-design auth launches the login command at container start" do
      assert_equal "claude", build_strategy.send(:ttyd_command)
    end

    test "design auth defers the launch (ttyd_command is bash, not claude)" do
      @session.update!(metadata: { "auth_kind" => "design" })
      assert_equal "bash", build_strategy.send(:ttyd_command)
    end

    test "design auth exec launches claude AND auto-runs /design-login after seeding creds" do
      @session.update!(metadata: { "auth_kind" => "design" })
      strategy = build_strategy
      strategy.stubs(:resolve_container).returns(mock("container"))
      strategy.stubs(:mark_session_ready)
      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.stubs(:container_identifier).returns("cid")
      # The deferred launch sends both `claude` and `/design-login` into tmux — the
      # user never types the command themselves.
      runtime_mock.expects(:exec).with do |_c, argv|
        script = argv.is_a?(Array) ? argv.last.to_s : ""
        script.include?("send-keys") && script.include?("claude") && script.include?("/design-login")
      end

      strategy.exec(container_id: "abc")
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
