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

    test "inherits from AgentBaseStrategy" do
      assert AgentSessionStrategy < AgentBaseStrategy
    end

    # == Environment Variables Tests ==

    test "builds env vars with agent_session type" do
      strategy = build_strategy

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "SESSION_TYPE=agent_session"
      refute env_vars.any? { |v| v == "SESSION_TYPE=auth_setup" }
    end

    test "does not include MCP env vars (MCP configured via config files)" do
      strategy = build_strategy

      env_vars = strategy.build_env_vars

      refute env_vars.any? { |v| v.start_with?("MCP_SERVER_URL=") }
      refute env_vars.any? { |v| v.start_with?("MCP_SESSION_KEY=") }
    end

    test "TTYD_CMD is bash for agent sessions" do
      strategy = build_strategy(agent_type: "claude_code")

      env_vars = strategy.build_env_vars
      ttyd_cmd = env_vars.find { |v| v.start_with?("TTYD_CMD=") }

      assert_equal "TTYD_CMD=bash", ttyd_cmd
    end

    # == Labels Tests ==

    test "builds labels with agent_session type" do
      strategy = build_strategy

      labels = strategy.build_labels

      assert_equal "agent_session", labels["palad.session_type"]
    end

    # == before_exec Tests ==

    test "before_exec loads credentials into container via assembler" do
      strategy = build_strategy

      container_mock = mock("container")
      ContainerRuntime.stubs(:build).returns(mock("rt").tap { |m| m.stubs(:resolve_container).returns(container_mock) })
      strategy.stubs(:resolve_container).returns(container_mock)

      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.expects(:container_identifier).with(container_mock).returns("abc123")

      SessionContextService.expects(:assemble_session_context).with(
        container_mock, @session, credential: @credential
      )

      strategy.before_exec(container_id: "container_ref")
    end

    test "before_exec skips credential when nil" do
      strategy = AgentSessionStrategy.new(
        user_id: @user.id,
        agent_type: "claude_code",
        session_id: @session.id,
        route_token: @session.route_token,
        credential: nil
      )

      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)

      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.expects(:container_identifier).with(container_mock).returns("abc123")

      SessionContextService.expects(:assemble_session_context).with(
        container_mock, @session, credential: nil
      )

      strategy.before_exec(container_id: "container_ref")
    end

    # == before_cleanup Tests ==

    test "before_cleanup sets logs_count and outputs_count in result" do
      strategy = build_strategy
      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)

      mock_adapter = mock("adapter")
      mock_adapter.stubs(:respond_to?).with(:session_log_paths).returns(false)
      mock_adapter.stubs(:respond_to?).with(:collect_usage).returns(false)

      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).returns(mock_service)

      strategy.stubs(:collect_outputs).returns(0)
      strategy.stubs(:collect_logs).returns([ 0, {} ])
      strategy.stubs(:collect_terminal_output).returns(0)
      strategy.stubs(:collect_usage)

      result = strategy.before_cleanup(container_id: "abc123")

      assert result.key?(:logs_count)
      assert result.key?(:outputs_count)
    end

    # == Full Flow Tests ==

    test "session_type returns agent_session" do
      strategy = build_strategy

      assert_equal "agent_session", strategy.send(:session_type)
    end

    test "services_ports returns ttyd and OpenVSCode Server ports without file watcher" do
      strategy = build_strategy

      ports = strategy.send(:services_ports)

      assert_includes ports, 7681
      assert_includes ports, 8443
      refute_includes ports, 4040
    end

    test "exec result does not include watcher_url" do
      strategy = build_strategy
      @session.update!(mode: "interactive")
      runtime_mock = mock("runtime")

      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)
      strategy.stubs(:mark_session_ready)

      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.stubs(:container_identifier).returns("abc123")
      runtime_mock.stubs(:exec)

      result = strategy.exec(container_id: "abc123")

      refute result.key?(:watcher_url)
      assert result.key?(:websocket_url)
      assert result.key?(:ide_url)
    end

    test "ttyd_command returns bash" do
      strategy = build_strategy(agent_type: "claude_code")

      cmd = strategy.send(:ttyd_command)

      assert_equal "bash", cmd
    end

    # == before_exec delegates to assembler ==

    test "before_exec delegates to SessionContextService.assemble_session_context" do
      strategy = build_strategy

      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)

      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.expects(:container_identifier).with(container_mock).returns("abc123")

      SessionContextService.expects(:assemble_session_context).with(
        container_mock, @session, credential: @credential
      )

      strategy.before_exec(container_id: "container_ref")
    end

    test "before_exec raises when container not ready" do
      strategy = build_strategy

      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)

      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.expects(:container_identifier).returns(nil)

      error = assert_raises(RuntimeError) do
        strategy.before_exec(container_id: "bad_ref")
      end
      assert_match(/Container not ready/, error.message)
    end

    # == before_cleanup Tests ==

    test "before_cleanup creates SessionLog records when adapter supports session_log_paths" do
      strategy = build_strategy
      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)

      mock_adapter = mock("adapter")
      mock_adapter.stubs(:respond_to?).with(:session_log_paths).returns(true)
      mock_adapter.stubs(:respond_to?).with(:collect_usage).returns(false)
      mock_adapter.stubs(:session_log_paths).returns([ "/tmp/session.log" ])

      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).returns(mock_service)

      strategy.stubs(:read_file_from_container).with(container_mock, "/tmp/session.log").returns("log content here")
      strategy.stubs(:collect_outputs).returns(0)
      strategy.stubs(:collect_terminal_output).returns(0)
      strategy.stubs(:collect_usage)

      assert_difference "SessionLog.count", 1 do
        result = strategy.before_cleanup(container_id: "abc123")
        assert_equal 1, result[:logs_count]
        assert_equal 0, result[:outputs_count]
      end

      log = @session.session_logs.last
      assert_equal "session.log", log.name
      assert_equal "log content here".bytesize, log.file_size
    end

    test "before_cleanup handles log collection errors gracefully" do
      strategy = build_strategy
      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)

      mock_adapter = mock("adapter")
      mock_adapter.stubs(:respond_to?).with(:session_log_paths).returns(true)
      mock_adapter.stubs(:respond_to?).with(:collect_usage).returns(false)
      mock_adapter.stubs(:session_log_paths).returns([ "/tmp/error.log" ])

      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).returns(mock_service)

      strategy.stubs(:read_file_from_container).raises(StandardError.new("Read error"))
      strategy.stubs(:collect_outputs).returns(0)
      strategy.stubs(:collect_terminal_output).returns(0)
      strategy.stubs(:collect_usage)

      result = strategy.before_cleanup(container_id: "abc123")

      assert_equal 0, result[:logs_count]
    end

    test "before_cleanup skips blank log content" do
      strategy = build_strategy
      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)

      mock_adapter = mock("adapter")
      mock_adapter.stubs(:respond_to?).with(:session_log_paths).returns(true)
      mock_adapter.stubs(:respond_to?).with(:collect_usage).returns(false)
      mock_adapter.stubs(:session_log_paths).returns([ "/tmp/empty.log" ])

      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).returns(mock_service)

      strategy.stubs(:read_file_from_container).returns(nil)
      strategy.stubs(:collect_outputs).returns(0)
      strategy.stubs(:collect_terminal_output).returns(0)
      strategy.stubs(:collect_usage)

      assert_no_difference "SessionLog.count" do
        result = strategy.before_cleanup(container_id: "abc123")
        assert_equal 0, result[:logs_count]
      end
    end

    test "before_cleanup collects usage when adapter supports it" do
      strategy = build_strategy
      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)

      mock_adapter = mock("adapter")
      mock_adapter.stubs(:respond_to?).with(:session_log_paths).returns(false)
      mock_adapter.stubs(:respond_to?).with(:collect_usage).returns(true)
      mock_adapter.expects(:collect_usage).with(@session, is_a(Hash))

      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).returns(mock_service)

      strategy.stubs(:collect_outputs).returns(0)
      strategy.stubs(:collect_logs).returns([ 0, {} ])
      strategy.stubs(:collect_terminal_output).returns(0)

      result = strategy.before_cleanup(container_id: "abc123")

      assert_equal 0, result[:logs_count]
      assert_equal 0, result[:outputs_count]
    end

    # == Credential metadata env vars ==

    test "builds env vars with credential metadata for gemini" do
      @session.update!(agent_type: "gemini_cli")
      @credential.update!(agent_type: "gemini_cli", metadata: { "google_cloud_project" => "my-project" })
      strategy = build_strategy(agent_type: "gemini_cli")

      env_vars = strategy.build_env_vars

      # GeminiCliAdapter no longer maps metadata to env vars (API key auth)
      refute env_vars.any? { |v| v == "GOOGLE_CLOUD_PROJECT=my-project" }
    end

    test "builds env vars skips blank credential metadata values" do
      @credential.update!(metadata: { "empty_key" => "" })
      strategy = build_strategy

      env_vars = strategy.build_env_vars

      refute env_vars.any? { |v| v.start_with?("empty_key=") }
    end

    test "launch_agent_in_tmux uses codex exec with AGENT_PROMPT for non_interactive codex sessions" do
      @session.update!(agent_type: "codex", mode: "non_interactive", initial_prompt: "Run tests")
      strategy = build_strategy(agent_type: "codex")
      container_mock = mock("container")

      mock_adapter = mock("adapter")
      mock_adapter.expects(:session_command).with(mode: "non_interactive", prompt: "Run tests")
                  .returns("codex exec --skip-git-repo-check --model gpt-5.3-codex")

      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.expects(:for).with("codex").returns(mock_service)

      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.expects(:exec).with do |container, command|
        container == container_mock &&
          command[0] == "sh" &&
          command[1] == "-c" &&
          command[2].include?('codex exec --skip-git-repo-check --model gpt-5.3-codex "$AGENT_PROMPT"')
      end

      strategy.send(:launch_agent_in_tmux, container_mock)
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
