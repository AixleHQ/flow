# frozen_string_literal: true

require "test_helper"

class ContainerWorkflowServiceTest < ActiveSupport::TestCase
  setup do
    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
    Rails.logger.stubs(:error)

    ContainerWorkflowService.instance_variable_set(:@agent_workflow, nil)
    ContainerWorkflowService.instance_variable_set(:@tool_workflow, nil)
  end

  teardown do
    ContainerWorkflowService.instance_variable_set(:@agent_workflow, nil)
    ContainerWorkflowService.instance_variable_set(:@tool_workflow, nil)
  end

  def create_test_objects
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @tool = create(:tool, scope: @company)
    @session = create(:terminal_session, user: @user)
  end

  # == start_session Tests ==

  test "start_session dispatches to AgentContainerWorkflow" do
    create_test_objects
    stub_agent_workflow

    expected_result = { ok: true, workflow_id: "agent-session-#{@session.id}", run_id: "run-456" }

    TemporalService.expects(:start_workflow).with(
      anything,
      has_entries(session_id: @session.id, mode: @session.mode),
      has_entries(
        id: "agent-session-#{@session.id}",
        execution_timeout: ContainerWorkflowService::AGENT_WORKFLOW_TIMEOUT
      )
    ).returns(expected_result)

    result = ContainerWorkflowService.start_session(session: @session)

    assert_equal expected_result, result
  end

  test "start_session works for auth_setup sessions" do
    create_test_objects
    @session.update_column(:session_type, "auth_setup")
    stub_agent_workflow

    expected_result = { ok: true, workflow_id: "agent-session-#{@session.id}", run_id: "run-789" }

    TemporalService.expects(:start_workflow).with(
      anything,
      has_entries(session_id: @session.id),
      has_key(:id)
    ).returns(expected_result)

    result = ContainerWorkflowService.start_session(session: @session)

    assert_equal expected_result, result
  end

  # == Tool Execution Tests ==

  test "starts tool execution workflow via TemporalService" do
    create_test_objects
    stub_tool_workflow

    expected_result = { ok: true, workflow_id: "tool-execution-123", run_id: "run-456" }

    TemporalService.expects(:start_workflow).with(
      anything,
      has_entries(tool_id: @tool.id, parameters: { "key" => "value" }, project_id: @project.id, timeout: 600),
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
    stub_tool_workflow

    expected_result = { exit_code: 0, stdout: "success" }

    TemporalService.expects(:execute_workflow).with(
      anything,
      has_entries(tool_id: @tool.id)
    ).returns(expected_result)

    result = ContainerWorkflowService.execute_tool(tool: @tool)

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

  def stub_agent_workflow
    mock_workflow = mock("agent_workflow_def")
    mock_workflow.stubs(:name).returns("agent_container_workflow")
    WorkflowService.stubs(:agent_container_workflow).returns(mock_workflow)
  end

  def stub_tool_workflow
    mock_workflow = mock("tool_workflow_def")
    mock_workflow.stubs(:name).returns("tool_execution_workflow")
    WorkflowService.stubs(:tool_execution_workflow).returns(mock_workflow)
  end
end
