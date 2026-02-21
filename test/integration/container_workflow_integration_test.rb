# frozen_string_literal: true

# Integration test: exercises all combinations of agent types, container runtimes,
# strategies and modes through the real PhaseActivity → ContainerService → Strategy → Runtime stack.
#
# Mocks only the lowest level (see StubSupport):
#   Docker:     Docker::Image, Docker::Container (command-routed exec)
#   Kubernetes: core_client, traefik_client, exec_via_websocket (command-routed)
#   Traefik:    WebMock
#
# Each agent type gets realistic fixture data: auth configs, MITM logs, outputs.
#
# Combinations:
#   Agent strategies:  4 agents × 2 runtimes × 2 strategies × 2 modes = 32 tests
#   Tool execution:    4 variants (basic, with params, with files, with project) = 4 tests

require "test_helper"

class ContainerWorkflowIntegrationTest < ActiveSupport::TestCase
  # ===========================================================================
  # Agent strategy combinations (32 tests)
  # ===========================================================================

  AGENT_TYPES = %w[claude_code cursor_cli codex gemini_cli].freeze
  CONTAINER_RUNTIMES = %w[docker kubernetes].freeze
  STRATEGIES = %w[auth_setup agent_session].freeze
  MODES = %w[interactive non_interactive].freeze

  AGENT_TYPES.each do |agent_type|
    CONTAINER_RUNTIMES.each do |container_runtime|
      STRATEGIES.each do |strategy|
        MODES.each do |mode|
          test "#{strategy} | #{agent_type} | #{container_runtime} | #{mode}" do
            Settings.stubs(:container_runtime).returns(container_runtime)
            stub_container_runtime(container_runtime, agent_type: agent_type)

            session = build_session(strategy, agent_type, mode)
            state = run_phases_for_session(session)
            session.reload

            assert_equal "finished", session.state,
              "Expected finished, got #{session.state}. Error: #{session.error_message}"

            assert state[:image].present?, "Expected image in state"
            assert state[:container_id].present?, "Expected container_id in state"
            assert_equal :cleaned_up, state[:status]

            if strategy == "auth_setup"
              assert_auth_credential_saved(session, agent_type)
            end

            if strategy == "agent_session"
              assert_session_logs_collected(session, agent_type)
            end
          end
        end
      end
    end
  end

  # ===========================================================================
  # Tool execution (Docker only, 4 tests)
  # ===========================================================================

  test "tool_execution | basic command" do
    tool = create(:tool, scope: @company, command: "echo hello", docker_image: "alpine:latest")

    state = run_phases_for_tool(tool)

    assert state[:image].present?
    assert state[:container_id].present?
    assert_equal :cleaned_up, state[:status]
    assert_equal 0, state[:exit_code]
    assert_equal false, state[:timed_out]
  end

  test "tool_execution | with parameters in command" do
    tool = create(:tool, scope: @company, command: "echo {{message}} > /workspace/out.txt",
                         docker_image: "python:3.12-slim")

    state = run_phases_for_tool(tool, parameters: { "message" => "hello world" })

    assert_equal 0, state[:exit_code]
    assert_equal :cleaned_up, state[:status]
  end

  test "tool_execution | with tool_files" do
    tool = create(:tool, scope: @company, command: "/bin/sh /workspace/scripts/run.sh",
                         docker_image: "node:20-slim")
    tool.tool_files.create!(path: "/workspace/scripts/run.sh", content: "#!/bin/sh\necho done")

    state = run_phases_for_tool(tool)

    assert_equal 0, state[:exit_code]
    assert_equal :cleaned_up, state[:status]
  end

  test "tool_execution | with project scope" do
    tool = create(:tool, scope: @project, command: "python run.py",
                         docker_image: "python:3.12-slim")

    state = run_phases_for_tool(tool, project: @project)

    assert_equal 0, state[:exit_code]
    assert_equal :cleaned_up, state[:status]
  end

  # ===========================================================================
  # Setup / Teardown
  # ===========================================================================

  setup do
    @company = create(:company, email_domain: "test.com")
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)

    stub_traefik_http
    stub_container_settings
  end

  teardown do
    cleanup_runtime_overrides
  end

  private

  # ---------------------------------------------------------------------------
  # Session helpers
  # ---------------------------------------------------------------------------

  def build_session(strategy, agent_type, mode)
    prompt = mode == "non_interactive" ? "do something" : nil

    case strategy
    when "auth_setup"
      create(:terminal_session, :auth_setup,
        user: @user, agent_type: agent_type, mode: mode,
        initial_prompt: prompt)
    when "agent_session"
      create(:agent_credential, user: @user, agent_type: agent_type)
      SessionContextService.stubs(:assemble_session_context)
      create(:terminal_session, :agent_session,
        user: @user, agent_type: agent_type, mode: mode,
        project: @project, initial_prompt: prompt)
    end
  end

  def run_phases_for_session(session)
    activity = Activities::Container::PhaseActivity.new
    state = {}

    %w[pull_image create_container start_container exec].each do |phase|
      input = Hashie::Mash.new(phase: phase, state: state, session_id: session.id)
      state = activity.run(input)
    end

    input = Hashie::Mash.new(phase: "cleanup", state: state, session_id: session.id)
    activity.run(input)
  end

  # ---------------------------------------------------------------------------
  # Tool helpers
  # ---------------------------------------------------------------------------

  def run_phases_for_tool(tool, parameters: {}, project: nil)
    Settings.stubs(:container_runtime).returns("docker")
    stub_container_runtime("docker", agent_type: "claude_code")

    activity = Activities::Container::PhaseActivity.new
    state = {}

    %w[pull_image create_container start_container exec].each do |phase|
      input = Hashie::Mash.new(
        phase: phase, state: state,
        tool_id: tool.id, parameters: parameters,
        project_id: project&.id, timeout: 10
      )
      state = activity.run(input)
    end

    input = Hashie::Mash.new(
      phase: "cleanup", state: state,
      tool_id: tool.id, parameters: parameters,
      project_id: project&.id, timeout: 10
    )
    activity.run(input)
  end

  # ---------------------------------------------------------------------------
  # Assertions
  # ---------------------------------------------------------------------------

  def assert_auth_credential_saved(session, agent_type)
    credential = AgentCredential.find_by(user_id: session.user_id, agent_type: agent_type)
    assert credential.present?, "Expected AgentCredential for #{agent_type}"
    data = credential.config_data
    assert data.is_a?(Hash), "Expected config_data to be a Hash"

    case agent_type
    when "claude_code"
      assert data["oauthAccount"].present?, "Expected oauthAccount in claude_code credential"
    when "cursor_cli"
      assert data["accessToken"].present?, "Expected accessToken in cursor_cli credential"
    when "codex"
      assert data["tokens"].present?, "Expected tokens in codex credential"
    when "gemini_cli"
      assert data["refresh_token"].present?, "Expected refresh_token in gemini_cli credential"
    end
  end

  def assert_session_logs_collected(session, agent_type)
    return if agent_type == "gemini_cli"

    logs = session.session_logs.reload
    assert logs.any?, "Expected session logs for #{agent_type} agent_session"
  end
end
