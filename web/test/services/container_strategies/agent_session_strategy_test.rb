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

    test "does not include MCP env vars (MCP configured via config files)" do
      strategy = build_strategy

      env_vars = strategy.build_env_vars

      refute env_vars.any? { |v| v.start_with?("MCP_SERVER_URL=") }
      refute env_vars.any? { |v| v.start_with?("MCP_SESSION_KEY=") }
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

      # Session command for cursor_cli is "agent --force" (yolo mode)
      assert_includes env_vars, "TTYD_CMD=agent --force"
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

    test "before_exec loads credentials into container via assembler" do
      strategy = build_strategy

      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.expects(:container_identifier).with("container_ref").returns("abc123")

      # Expect assemble_session_context to be called with credential
      SessionContextService.expects(:assemble_session_context).with(
        "container_ref", @session, credential: @credential
      )

      context = { container: "container_ref" }
      strategy.before_exec(context)
    end

    test "before_exec skips credential when nil" do
      strategy = AgentSessionStrategy.new(
        user_id: @user.id,
        agent_type: "claude_code",
        session_id: @session.id,
        route_token: @session.route_token,
        credential: nil
      )

      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.expects(:container_identifier).with("container_ref").returns("abc123")

      # Expect assemble_session_context to be called with credential: nil
      SessionContextService.expects(:assemble_session_context).with(
        "container_ref", @session, credential: nil
      )

      context = { container: "container_ref" }
      strategy.before_exec(context)
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

    test "services_ports returns ttyd and file watcher ports" do
      strategy = build_strategy

      ports = strategy.send(:services_ports)

      assert_includes ports, 7681 # ttyd
      assert_includes ports, 4040 # file watcher
    end

    test "ttyd_command returns session command for claude_code" do
      strategy = build_strategy(agent_type: "claude_code")

      cmd = strategy.send(:ttyd_command)

      assert_equal "claude", cmd
    end

    test "ttyd_command returns non-interactive command when mode is non_interactive" do
      @session.update!(session_config: {
        "mode" => "non_interactive",
        "initial_prompt" => "Fix the tests"
      })
      strategy = build_strategy(agent_type: "claude_code")

      cmd = strategy.send(:ttyd_command)

      # Prompt is passed via AGENT_PROMPT env var, not in command
      assert_equal "claude", cmd
    end

    test "ttyd_command uses adapter session_command for codex non-interactive" do
      @session.update!(agent_type: "codex", session_config: {
        "mode" => "non_interactive",
        "initial_prompt" => "Run all tests"
      })
      @credential.update!(agent_type: "codex")
      strategy = build_strategy(agent_type: "codex")

      cmd = strategy.send(:ttyd_command)

      # Prompt is passed via AGENT_PROMPT env var, not in command
      assert_equal "codex -q", cmd
    end

    # == before_exec delegates to assembler ==

    test "before_exec delegates to SessionContextService.assemble_session_context" do
      strategy = build_strategy

      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.expects(:container_identifier).with("container_ref").returns("abc123")

      SessionContextService.expects(:assemble_session_context).with(
        "container_ref", @session, credential: @credential
      )

      context = { container: "container_ref" }
      strategy.before_exec(context)
    end

    test "before_exec raises when container not ready" do
      strategy = build_strategy

      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.expects(:container_identifier).returns(nil)

      assert_raises(RuntimeError, /Container not ready/) do
        strategy.before_exec(container: "bad_ref")
      end
    end

    test "list_files_in_container returns path directly for non-glob" do
      strategy = build_strategy
      container_mock = mock("container")

      files = strategy.send(:list_files_in_container, container_mock, "/path/to/file.log")

      assert_equal [ "/path/to/file.log" ], files
    end

    test "list_files_in_container executes find for glob pattern" do
      strategy = build_strategy
      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)

      runtime_mock.expects(:exec).with(
        "container_ref",
        [ "/bin/sh", "-c", "find /tmp -name '*.log' 2>/dev/null || true" ],
        stdout: true,
        stderr: true
      ).returns([ [ "/tmp/app.log\n/tmp/error.log\n" ], [], 0 ])

      files = strategy.send(:list_files_in_container, "container_ref", "/tmp/*.log")

      assert_equal [ "/tmp/app.log", "/tmp/error.log" ], files
    end

    test "list_files_in_container returns empty array on error" do
      strategy = build_strategy
      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)

      runtime_mock.expects(:exec).raises(StandardError.new("Exec failed"))

      files = strategy.send(:list_files_in_container, "container_ref", "/tmp/*.log")

      assert_equal [], files
    end

    test "list_files_in_container returns empty array on non-zero exit" do
      strategy = build_strategy
      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)

      runtime_mock.expects(:exec).returns([ [], [], 1 ])

      files = strategy.send(:list_files_in_container, "container_ref", "/tmp/*.log")

      assert_equal [], files
    end

    # == before_cleanup with artifacts Tests ==

    test "before_cleanup collects session logs when adapter supports session_log_paths" do
      strategy = build_strategy
      container_mock = mock("container")

      # Mock adapter with session_log_paths
      mock_adapter = mock("adapter")
      mock_adapter.stubs(:respond_to?).with(:session_log_paths).returns(true)
      mock_adapter.stubs(:respond_to?).with(:output_artifact_paths).returns(false)
      mock_adapter.stubs(:respond_to?).with(:collect_usage).returns(false)
      mock_adapter.stubs(:session_log_paths).returns([ "/tmp/session.log" ])

      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).returns(mock_service)

      # Mock file reading
      strategy.stubs(:read_file_from_container).with(container_mock, "/tmp/session.log").returns("log content")

      context = { container: container_mock }
      strategy.before_cleanup(context)

      assert context[:result][:artifacts]["logs/session.log"].present?
      assert_equal "log content", context[:result][:artifacts]["logs/session.log"]
    end

    test "before_cleanup handles log collection errors gracefully" do
      strategy = build_strategy
      container_mock = mock("container")

      mock_adapter = mock("adapter")
      mock_adapter.stubs(:respond_to?).with(:session_log_paths).returns(true)
      mock_adapter.stubs(:respond_to?).with(:output_artifact_paths).returns(false)
      mock_adapter.stubs(:respond_to?).with(:collect_usage).returns(false)
      mock_adapter.stubs(:session_log_paths).returns([ "/tmp/error.log" ])

      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).returns(mock_service)

      # Simulate error when reading file
      strategy.stubs(:read_file_from_container).raises(StandardError.new("Read error"))

      context = { container: container_mock }
      # Should not raise
      strategy.before_cleanup(context)

      assert context[:result][:artifacts_count] == 0
    end

    test "before_cleanup collects output artifacts when adapter supports output_artifact_paths" do
      strategy = build_strategy
      container_mock = mock("container")

      mock_adapter = mock("adapter")
      mock_adapter.stubs(:respond_to?).with(:session_log_paths).returns(false)
      mock_adapter.stubs(:respond_to?).with(:output_artifact_paths).returns(true)
      mock_adapter.stubs(:respond_to?).with(:collect_usage).returns(false)
      mock_adapter.stubs(:output_artifact_paths).returns([ "/output/*.json" ])

      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).returns(mock_service)

      # Mock list_files_in_container
      strategy.stubs(:list_files_in_container).with(container_mock, "/output/*.json").returns([ "/output/data.json" ])
      strategy.stubs(:read_file_from_container).with(container_mock, "/output/data.json").returns('{"result": "ok"}')

      context = { container: container_mock }
      strategy.before_cleanup(context)

      assert context[:result][:artifacts]["/output/data.json"].present?
      assert_equal '{"result": "ok"}', context[:result][:artifacts]["/output/data.json"]
    end

    test "before_cleanup handles file listing errors gracefully" do
      strategy = build_strategy
      container_mock = mock("container")

      mock_adapter = mock("adapter")
      mock_adapter.stubs(:respond_to?).with(:session_log_paths).returns(false)
      mock_adapter.stubs(:respond_to?).with(:output_artifact_paths).returns(true)
      mock_adapter.stubs(:respond_to?).with(:collect_usage).returns(false)
      mock_adapter.stubs(:output_artifact_paths).returns([ "/error/*.json" ])

      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).returns(mock_service)

      # list_files_in_container raises error
      strategy.stubs(:list_files_in_container).raises(StandardError.new("List error"))

      context = { container: container_mock }
      # Should not raise
      strategy.before_cleanup(context)

      assert context[:result].present?
    end

    # == Credential metadata env vars ==

    test "builds env vars with credential metadata for gemini" do
      @session.update!(agent_type: "gemini_cli")
      @credential.update!(agent_type: "gemini_cli", metadata: { "google_cloud_project" => "my-project" })
      strategy = build_strategy(agent_type: "gemini_cli")

      env_vars = strategy.build_env_vars

      assert env_vars.any? { |v| v == "GOOGLE_CLOUD_PROJECT=my-project" }
    end

    test "builds env vars skips blank credential metadata values" do
      @credential.update!(metadata: { "empty_key" => "" })
      strategy = build_strategy

      env_vars = strategy.build_env_vars

      refute env_vars.any? { |v| v.start_with?("empty_key=") }
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
