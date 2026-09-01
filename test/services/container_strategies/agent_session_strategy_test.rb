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

    # == Model resolution is per company ==
    #
    # The default model is pinned on a credential, and a credential belongs to one
    # company. A pin made against another company's Bedrock account does not exist here,
    # so launching on it would leave every session on a model that never answers.

    test "resolve_model prefers the pin on this session's company credential" do
      @credential.update!(metadata: { "default_model" => "mine" })
      other_credential_with_pin("other-tenant-model")

      assert_equal "mine", build_strategy.send(:resolve_model, @session)
    end

    test "resolve_model ignores a pin that belongs to another company" do
      other_credential_with_pin("other-tenant-model")

      assert_nil build_strategy.send(:resolve_model, @session)
    end

    # A pin the vendor has since retired answers 404, so launching on it would fail
    # every session until the user noticed and re-picked.
    test "resolve_model launches a retired pin on its replacement" do
      @credential.update!(metadata: { "default_model" => "claude-3-7-sonnet-20250219" })

      assert_equal "claude-sonnet-5", build_strategy.send(:resolve_model, @session)
    end

    # == Inheritance Tests ==

    test "inherits from AgentBaseStrategy" do
      assert_operator AgentSessionStrategy, :<, AgentBaseStrategy
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

      assert_equal "agent_session", labels["aixle.session_type"]
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
      strategy.stubs(:persist_refreshed_credentials)
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
      strategy.stubs(:persist_refreshed_credentials)
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
      strategy.stubs(:persist_refreshed_credentials)
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
      strategy.stubs(:persist_refreshed_credentials)
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
      strategy.stubs(:persist_refreshed_credentials)

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

    # == Grok ==

    test "builds env vars for a grok session with the company API key and MITM tracking" do
      @session.update!(agent_type: "grok")
      @credential.update!(agent_type: "grok", config_data: { "api_key" => "xai-company-key" })
      strategy = build_strategy(agent_type: "grok")

      env_vars = strategy.build_env_vars

      assert_includes env_vars, "AGENT_TYPE=grok"
      assert_includes env_vars, "HOME_DIR=/home/grok"
      assert_includes env_vars, "AUTH_WATCH_PATH=/home/grok/.grok/auth.json"
      assert_includes env_vars, "MITM_TRACKED_DOMAINS=x.ai,grok.com"
      assert_includes env_vars, "XAI_API_KEY=xai-company-key"
    end

    # == Conflicting provider env ==
    #
    # XAI_API_KEY outranks a stored session token in the Grok CLI's own credential
    # resolution, so a key left in the environment would silently bill a different
    # xAI account than the one the user signed in with. `scrub_conflicting_auth_env`
    # runs last, after every other env source has had its say.
    #
    # There is deliberately no arbitrary per-session env channel any more: a session
    # reaches its config items through the `get_config_item` MCP tool and nothing is
    # injected into the container (see spec-session-config-item-access). The adapters'
    # own `default_env_vars` are therefore the only producer left, and the scrub stays
    # as the net for them. Per-adapter key lists are covered in the adapter tests.

    test "build_env_vars keeps XAI_API_KEY when the grok credential is an API-key login" do
      @session.update!(agent_type: "grok")
      @credential.update!(agent_type: "grok", config_data: { "api_key" => "xai-company-key" })

      env_vars = build_strategy(agent_type: "grok").build_env_vars

      assert_includes env_vars, "XAI_API_KEY=xai-company-key"
    end

    test "build_env_vars carries no XAI_API_KEY when the grok credential is a session token" do
      @session.update!(agent_type: "grok")
      @credential.update!(agent_type: "grok", config_data: {
        "auth" => { "https://accounts.x.ai/sign-in" => { "key" => "session-token" } }
      })

      env_vars = build_strategy(agent_type: "grok").build_env_vars

      assert_not env_vars.any? { |v| v.start_with?("XAI_API_KEY=") }
    end

    test "build_env_vars injects no config item values — the MCP tool is the only channel" do
      project = create(:project, company: @company, owner: @user)
      @session.update!(project: project)
      @session.config_items << create(:config_item, :secret, scope: project, name: "STRIPE_KEY",
                                                            value: "sk_live_abc123")

      env_vars = build_strategy.build_env_vars

      assert_not env_vars.any? { |v| v.include?("sk_live_abc123") }
      assert_not env_vars.any? { |v| v.start_with?("STRIPE_KEY=") }
    end

    test "builds env vars skips blank credential metadata values" do
      @credential.update!(metadata: { "empty_key" => "" })
      strategy = build_strategy

      env_vars = strategy.build_env_vars

      refute env_vars.any? { |v| v.start_with?("empty_key=") }
    end

    test "launch_agent_in_tmux uses codex with AGENT_PROMPT for non_interactive codex sessions" do
      @session.update!(agent_type: "codex", mode: "non_interactive", initial_prompt: "Run tests")
      strategy = build_strategy(agent_type: "codex")
      container_mock = mock("container")

      mock_adapter = mock("adapter")
      mock_adapter.expects(:session_command).with(mode: "non_interactive", prompt: "Run tests", model: nil)
                  .returns("codex --yolo")

      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.expects(:for).with("codex").returns(mock_service)

      runtime_mock = mock("runtime")
      strategy.stubs(:runtime).returns(runtime_mock)
      runtime_mock.expects(:exec).with do |container, command|
        send_keys = command[2].match(/tmux send-keys -t agent (.+?) Enter;/)&.[](0)
        delivered_command = Shellwords.split(send_keys).fetch(4)

        container == container_mock &&
          command[0] == "sh" &&
          command[1] == "-c" &&
          delivered_command == 'codex --yolo "$AGENT_PROMPT"'
      end

      strategy.send(:launch_agent_in_tmux, container_mock)
    end

    # == collect_terminal_output (raw pipe-pane log → single SessionLog) ==

    test "collect_terminal_output stores the raw terminal log as a text/plain SessionLog" do
      fake = ContainerRuntime::FakeRuntime.new(agent_type: "claude_code", filesystem: {
        "/tmp/terminal_output.log" => "\e[31mred\e[0m done"
      })
      ContainerRuntime.stubs(:build).returns(fake)
      strategy = build_strategy

      assert_difference "SessionLog.count", 1 do
        assert_equal 1, strategy.send(:collect_terminal_output, "abc123", @session)
      end

      log = @session.session_logs.last
      assert_equal "terminal_output.log", log.name
      assert_equal "text/plain; charset=utf-8", log.content_type
      assert_equal "\e[31mred\e[0m done".bytesize, log.file_size
      refute fake.execs.any? { |cmd| cmd.join(" ").include?("capture-pane") },
             "collect_terminal_output must not run capture-pane (pipe-pane already wrote the file)"
    end

    test "collect_terminal_output skips blank content" do
      fake = ContainerRuntime::FakeRuntime.new(agent_type: "claude_code", filesystem: {
        "/tmp/terminal_output.log" => ""
      })
      ContainerRuntime.stubs(:build).returns(fake)
      strategy = build_strategy

      assert_no_difference "SessionLog.count" do
        assert_equal 0, strategy.send(:collect_terminal_output, "abc123", @session)
      end
    end

    # == persist_refreshed_credentials (#2: capture tokens refreshed mid-session) ==

    test "persist_refreshed_credentials updates existing credential when token changed" do
      @credential.update!(config_data: { "claudeAiOauth" => { "accessToken" => "old", "refreshToken" => "r1" } })
      strategy = build_strategy
      container = mock("container")
      agent_service = AgentCredentialsService.for("claude_code")
      strategy.stubs(:read_file_from_container).returns(nil)
      strategy.stubs(:read_file_from_container).with(container, "/home/claude/.claude.json").returns({}.to_json)
      strategy.stubs(:read_file_from_container)
              .with(container, "/home/claude/.claude/.credentials.json")
              .returns({ "claudeAiOauth" => { "accessToken" => "NEW", "refreshToken" => "r2" } }.to_json)

      strategy.send(:persist_refreshed_credentials, container, @session, agent_service)

      assert_equal "NEW", @credential.reload.config_data.dig("claudeAiOauth", "accessToken")
    end

    test "persist_refreshed_credentials is a no-op when the token is unchanged" do
      @credential.update!(config_data: { "claudeAiOauth" => { "accessToken" => "same" } })
      strategy = build_strategy
      container = mock("container")
      agent_service = AgentCredentialsService.for("claude_code")
      strategy.stubs(:read_file_from_container).returns(nil)
      strategy.stubs(:read_file_from_container).with(container, "/home/claude/.claude.json").returns({}.to_json)
      strategy.stubs(:read_file_from_container)
              .with(container, "/home/claude/.claude/.credentials.json")
              .returns({ "claudeAiOauth" => { "accessToken" => "same" } }.to_json)

      AgentCredential.expects(:from_artifacts).never

      strategy.send(:persist_refreshed_credentials, container, @session, agent_service)
    end

    test "persist_refreshed_credentials does not overwrite a newer stored token with an older one" do
      # A concurrent session refreshed first (stored token, expiresAt 2000); this
      # container still holds the older, now-rotated token (expiresAt 1000).
      @credential.update!(config_data: { "claudeAiOauth" => { "accessToken" => "live", "expiresAt" => 2000 } })
      strategy = build_strategy
      container = mock("container")
      agent_service = AgentCredentialsService.for("claude_code")
      strategy.stubs(:read_file_from_container).returns(nil)
      strategy.stubs(:read_file_from_container).with(container, "/home/claude/.claude.json").returns({}.to_json)
      strategy.stubs(:read_file_from_container)
              .with(container, "/home/claude/.claude/.credentials.json")
              .returns({ "claudeAiOauth" => { "accessToken" => "stale", "expiresAt" => 1000 } }.to_json)

      strategy.send(:persist_refreshed_credentials, container, @session, agent_service)

      assert_equal "live", @credential.reload.config_data.dig("claudeAiOauth", "accessToken")
    end

    test "resolve_output_scope falls back to the user's active membership company" do
      strategy = build_strategy
      @session.update_columns(project_id: nil)

      assert_equal [ "Company", @company.id ], strategy.send(:resolve_output_scope, @session.reload)
    end

    test "resolve_output_scope raises for a project-less session of a user with no active membership" do
      strategy = build_strategy
      @session.update_columns(project_id: nil)
      @user.company_memberships.each { |m| m.update_columns(state: "revoked") }

      error = assert_raises(RuntimeError) { strategy.send(:resolve_output_scope, @session.reload) }
      assert_match(/no active membership/, error.message)
    end

    test "persist_refreshed_credentials does not create a credential when none exists" do
      @credential.destroy!
      strategy = build_strategy
      container = mock("container")
      agent_service = AgentCredentialsService.for("claude_code")
      strategy.stubs(:read_file_from_container).returns(nil)
      strategy.stubs(:read_file_from_container).with(container, "/home/claude/.claude.json").returns({}.to_json)
      strategy.stubs(:read_file_from_container)
              .with(container, "/home/claude/.claude/.credentials.json")
              .returns({ "claudeAiOauth" => { "accessToken" => "NEW" } }.to_json)

      assert_no_difference "AgentCredential.count" do
        strategy.send(:persist_refreshed_credentials, container, @session, agent_service)
      end
    end

    # == collect_outputs (nested output dirs — session #61 regression) ==

    test "collect_outputs recurses subdirectories and names assets by path relative to outputs" do
      # Session 61: the agent wrote its deliverable into /workspace/outputs/presentation/*.
      # A `find -maxdepth 1` scan collected zero of them. Guard: nested files are collected,
      # and the path relative to outputs (not the bare basename) becomes the asset name — so
      # two files sharing a basename across subdirs both survive the name-uniqueness index.
      fake = ContainerRuntime::FakeRuntime.new(agent_type: "claude_code", filesystem: {
        "/workspace/outputs/presentation/index.html"      => "<html>deck</html>",
        "/workspace/outputs/presentation/assets/logo.svg" => "<svg>brand</svg>",
        "/workspace/outputs/notes/logo.svg"               => "<svg>other</svg>",
        "/workspace/outputs/report.md"                    => "# top level"
      })
      ContainerRuntime.stubs(:build).returns(fake)
      strategy = build_strategy

      count = nil
      assert_difference "Asset.count", 4 do
        count = strategy.send(:collect_outputs, "abc123", @session)
      end

      assert_equal 4, count
      names = @session.output_assets.pluck(:name)
      assert_includes names, "presentation/index.html"
      assert_includes names, "presentation/assets/logo.svg"
      assert_includes names, "notes/logo.svg"
      assert_includes names, "report.md"

      refute fake.execs.any? { |cmd| cmd.join(" ").include?("-maxdepth") },
             "collect_outputs must not cap find depth"
    end

    test "collect_outputs skips blank files" do
      fake = ContainerRuntime::FakeRuntime.new(agent_type: "claude_code", filesystem: {
        "/workspace/outputs/empty.txt" => ""
      })
      ContainerRuntime.stubs(:build).returns(fake)
      strategy = build_strategy

      assert_no_difference "Asset.count" do
        assert_equal 0, strategy.send(:collect_outputs, "abc123", @session)
      end
    end

    private

    # A second company the same person works for, holding its own claude_code credential
    # with its own default-model pin.
    def other_credential_with_pin(model)
      other_company = create(:company)
      create(:company_membership, user: @user, company: other_company)
      create(:agent_credential, user: @user, company: other_company, agent_type: "claude_code",
                                metadata: { "default_model" => model })
    end

    # == refresh_credential_if_expiring ==

    test "before_exec refreshes credential when token expires within threshold" do
      @credential.update!(expires_at: 30.minutes.from_now)
      strategy = build_strategy

      mock_adapter = mock("adapter")
      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).with("claude_code").returns(mock_service)
      mock_adapter.expects(:refresh!).with(@credential).returns({ status: :refreshed, detail: nil })
      @credential.stubs(:reload)

      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)
      strategy.stubs(:runtime).returns(mock("rt").tap { |m| m.stubs(:container_identifier).returns("abc") })
      SessionContextService.expects(:assemble_session_context)

      strategy.before_exec(container_id: "container_ref")
    end

    test "before_exec refreshes credential when token is already expired" do
      @credential.update!(expires_at: 5.minutes.ago)
      strategy = build_strategy

      mock_adapter = mock("adapter")
      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).with("claude_code").returns(mock_service)
      mock_adapter.expects(:refresh!).with(@credential).returns({ status: :refreshed, detail: nil })
      @credential.stubs(:reload)

      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)
      strategy.stubs(:runtime).returns(mock("rt").tap { |m| m.stubs(:container_identifier).returns("abc") })
      SessionContextService.expects(:assemble_session_context)

      strategy.before_exec(container_id: "container_ref")
    end

    test "before_exec refreshes credential when token expires exactly at threshold boundary" do
      @credential.update!(expires_at: AgentSessionStrategy::SESSION_REFRESH_THRESHOLD.from_now)
      strategy = build_strategy

      mock_adapter = mock("adapter")
      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).with("claude_code").returns(mock_service)
      mock_adapter.expects(:refresh!).with(@credential).returns({ status: :refreshed, detail: nil })
      @credential.stubs(:reload)

      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)
      strategy.stubs(:runtime).returns(mock("rt").tap { |m| m.stubs(:container_identifier).returns("abc") })
      SessionContextService.expects(:assemble_session_context)

      strategy.before_exec(container_id: "container_ref")
    end

    test "before_exec skips refresh when token expires far in the future" do
      @credential.update!(expires_at: 2.hours.from_now)
      strategy = build_strategy

      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)
      strategy.stubs(:runtime).returns(mock("rt").tap { |m| m.stubs(:container_identifier).returns("abc") })
      SessionContextService.expects(:assemble_session_context)

      strategy.before_exec(container_id: "container_ref")
    end

    test "before_exec skips refresh when credential has no expiry" do
      @credential.update!(expires_at: nil)
      strategy = build_strategy

      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)
      strategy.stubs(:runtime).returns(mock("rt").tap { |m| m.stubs(:container_identifier).returns("abc") })
      SessionContextService.expects(:assemble_session_context)

      strategy.before_exec(container_id: "container_ref")
    end

    test "before_exec fails session and raises when claude_code refresh returns invalid_grant" do
      @credential.update!(expires_at: 30.minutes.from_now)
      strategy = build_strategy

      mock_adapter = mock("adapter")
      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).with("claude_code").returns(mock_service)
      mock_adapter.stubs(:refresh!).returns({ status: :error, detail: "claudeAiOauth invalid_grant — reconnection required" })

      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)
      strategy.stubs(:runtime).returns(mock("rt").tap { |m| m.stubs(:container_identifier).returns("abc") })
      SessionService.expects(:fail_session).with(session: @session, error_message: anything)
      SessionContextService.expects(:assemble_session_context).never

      assert_raises(AgentSessionStrategy::InvalidGrantError) do
        strategy.before_exec(container_id: "container_ref")
      end
    end

    test "before_exec continues when refresh raises" do
      @credential.update!(expires_at: 30.minutes.from_now)
      strategy = build_strategy

      mock_adapter = mock("adapter")
      mock_service = mock("service")
      mock_service.stubs(:adapter).returns(mock_adapter)
      AgentCredentialsService.stubs(:for).with("claude_code").returns(mock_service)
      mock_adapter.stubs(:refresh!).raises(StandardError, "network timeout")

      container_mock = mock("container")
      strategy.stubs(:resolve_container).returns(container_mock)
      strategy.stubs(:runtime).returns(mock("rt").tap { |m| m.stubs(:container_identifier).returns("abc") })
      SessionContextService.expects(:assemble_session_context)

      strategy.before_exec(container_id: "container_ref")
    end

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
