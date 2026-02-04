# frozen_string_literal: true

require "test_helper"

class ContainerWorkflowServiceTest < ActiveSupport::TestCase
  setup do
    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
    Rails.logger.stubs(:error)

    # Reset memoized workflow
    ContainerWorkflowService.instance_variable_set(:@workflow, nil)
  end

  def create_test_objects
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @tool = create(:tool, scope: @company)
    @session = create(:terminal_session, user: @user)
    @credential = create(:agent_credential, user: @user)
  end

  # == Image Resolution Tests ==

  test "resolves claude_code image" do
    image = ContainerWorkflowService.send(:resolve_agent_image, "claude_code")
    assert_equal "palad/claude-code:latest", image
  end

  test "resolves cursor_cli image" do
    image = ContainerWorkflowService.send(:resolve_agent_image, "cursor_cli")
    assert_equal "palad/cursor-cli:latest", image
  end

  test "resolves codex image" do
    image = ContainerWorkflowService.send(:resolve_agent_image, "codex")
    assert_equal "palad/codex:latest", image
  end

  test "resolves gemini_cli image" do
    image = ContainerWorkflowService.send(:resolve_agent_image, "gemini_cli")
    assert_equal "palad/gemini-cli:latest", image
  end

  test "raises error for unknown agent type" do
    error = assert_raises(ArgumentError) do
      ContainerWorkflowService.send(:resolve_agent_image, "unknown")
    end
    assert_match(/Unknown agent type/, error.message)
  end

  # == Tool Execution Tests ==

  test "starts tool execution workflow via TemporalService" do
    create_test_objects
    stub_workflow_service

    expected_result = { ok: true, workflow_id: "tool-execution-123", run_id: "run-456" }

    TemporalService.expects(:start_workflow).with(
      anything,
      has_entries(
        strategy_type: "tool_execution",
        image: @tool.docker_image,
        strategy_input: has_entries(
          tool_id: @tool.id,
          parameters: { "key" => "value" },
          project_id: @project.id,
          timeout: 600
        )
      ),
      has_entries(execution_timeout: ContainerWorkflowService::TOOL_WORKFLOW_TIMEOUT)
    ).returns(expected_result)

    result = ContainerWorkflowService.start_tool_execution(
      tool: @tool,
      parameters: { "key" => "value" },
      project: @project,
      timeout: 600
    )

    assert_equal expected_result, result
  end

  test "executes tool and waits for result" do
    create_test_objects
    stub_workflow_service

    expected_result = { exit_code: 0, stdout: "success" }

    TemporalService.expects(:execute_workflow).with(
      anything,
      has_entries(strategy_type: "tool_execution")
    ).returns(expected_result)

    result = ContainerWorkflowService.execute_tool(tool: @tool)

    assert_equal expected_result, result
  end

  # == Agent Auth Tests ==

  test "starts agent auth workflow via TemporalService" do
    create_test_objects
    stub_workflow_service

    expected_result = { ok: true, workflow_id: "agent-auth-#{@session.id}", run_id: "run-456" }

    TemporalService.expects(:start_workflow).with(
      anything,
      has_entries(
        strategy_type: "agent_auth",
        image: "palad/claude-code:latest",
        strategy_input: has_entries(
          user_id: @session.user_id,
          agent_type: "claude_code",
          session_id: @session.id
        )
      ),
      has_entries(
        id: "agent-auth-#{@session.id}",
        execution_timeout: ContainerWorkflowService::AGENT_WORKFLOW_TIMEOUT
      )
    ).returns(expected_result)

    result = ContainerWorkflowService.start_agent_auth(session: @session)

    assert_equal expected_result, result
  end

  # == Agent Session Tests ==

  test "starts agent session workflow with credential" do
    create_test_objects
    stub_workflow_service

    expected_result = { ok: true, workflow_id: "agent-session-#{@session.id}", run_id: "run-456" }

    TemporalService.expects(:start_workflow).with(
      anything,
      has_entries(
        strategy_type: "agent_session",
        strategy_input: has_entries(credential_id: @credential.id)
      ),
      has_entries(id: "agent-session-#{@session.id}")
    ).returns(expected_result)

    result = ContainerWorkflowService.start_agent_session(
      session: @session,
      credential: @credential
    )

    assert_equal expected_result, result
  end

  test "starts agent session workflow without credential" do
    create_test_objects
    stub_workflow_service

    expected_result = { ok: true, workflow_id: "agent-session-#{@session.id}", run_id: "run-456" }

    TemporalService.expects(:start_workflow).with(
      anything,
      has_entries(
        strategy_type: "agent_session",
        strategy_input: has_entries(credential_id: nil)
      ),
      has_key(:id)
    ).returns(expected_result)

    result = ContainerWorkflowService.start_agent_session(session: @session)

    assert_equal expected_result, result
  end

  # == Signal Tests ==

  test "signals workflow via TemporalService" do
    TemporalService.expects(:send_signal).with("workflow-123", :container_finished).returns({ ok: true })

    result = ContainerWorkflowService.signal_workflow("workflow-123", signal: :container_finished)

    assert result[:ok]
  end

  test "cancels workflow via TemporalService" do
    TemporalService.expects(:cancel_workflow).with("workflow-123").returns({ ok: true })

    result = ContainerWorkflowService.cancel_workflow("workflow-123")

    assert result[:ok]
  end

  private

  def stub_workflow_service
    mock_workflow = mock("workflow_def")
    mock_workflow.stubs(:name).returns("unified_container_workflow")
    mock_workflow.stubs(:owner).returns("web")
    WorkflowService.stubs(:unified_container_workflow).returns(mock_workflow)
  end
end
