# frozen_string_literal: true

require "test_helper"

class SessionServiceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.company
    @project = create(:project, owner: @user, company: @company)
  end

  # == create_and_start ==

  test "create_and_start creates session and starts temporal workflow" do
    mock_temporal_start

    session = SessionService.create_and_start(
      user: @user,
      project: @project,
      session_type: "agent_session",
      agent_type: "claude_code"
    )

    assert session.persisted?
    assert_equal "running", session.state
    assert_equal "agent_session", session.session_type
    assert_equal "claude_code", session.agent_type
    assert_equal @project.id, session.project_id
    assert_not_nil session.temporal_workflow_id
  end

  test "create_and_start returns unsaved session on validation failure" do
    session = SessionService.create_and_start(
      user: @user,
      session_type: "auth_setup",
      agent_type: nil
    )

    assert_not session.persisted?
    assert session.errors.any?
  end

  test "create_and_start passes extra params" do
    mock_temporal_start

    session = SessionService.create_and_start(
      user: @user,
      session_type: "agent_session",
      agent_type: "claude_code",
      project: @project,
      params: {
        mode: "non_interactive",
        initial_prompt: "Run tests"
      }
    )

    assert session.persisted?
    assert_equal "non_interactive", session.mode
    assert_equal "Run tests", session.initial_prompt
  end

  # == finish ==

  test "finish sends container_finished signal" do
    session = create(:terminal_session, :running, user: @user, temporal_workflow_id: "wf-123")

    TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, nil).once

    SessionService.finish(session: session)
  end

  test "finish signals workflow execution for workflow_step sessions" do
    workflow_run = create(:workflow_run, project: @project, user: @user)
    step = create(:step, workflow: workflow_run.workflow)
    step_run = create(:step_run, workflow_run: workflow_run, step: step)
    session = create(:terminal_session, :running, user: @user, session_type: "workflow_step",
                     temporal_workflow_id: "wf-456", project: @project)
    step_run.update!(terminal_session: session)

    TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, step_run.id).once
    TemporalService.expects(:send_signal).with("workflow-execution-#{workflow_run.id}", :container_finished, step_run.id).once

    SessionService.finish(session: session)
  end

  test "finish raises InvalidStateError for non-finishable session" do
    session = create(:terminal_session, user: @user, state: "finished")

    assert_raises(TerminalSession::InvalidStateError) do
      SessionService.finish(session: session)
    end
  end

  # == cancel ==

  test "cancel cancels temporal workflow and fails session" do
    session = create(:terminal_session, :running, user: @user, temporal_workflow_id: "wf-789")

    TemporalService.expects(:cancel_workflow).with(session.workflow_id).once

    SessionService.cancel(session: session)

    session.reload
    assert_equal "failed", session.state
  end

  test "cancel without temporal workflow just fails session" do
    session = create(:terminal_session, :running, user: @user, temporal_workflow_id: nil)

    SessionService.cancel(session: session)

    session.reload
    assert_equal "failed", session.state
  end

  # == create_for_workflow_step ==

  test "create_for_workflow_step creates session bound to step_run" do
    mock_temporal_start

    workflow = create(:workflow, scope: @company)
    step = create(:step, workflow: workflow, instructions: "Do the thing")
    workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    step_run = create(:step_run, workflow_run: workflow_run, step: step)

    SessionConfigResolver.stubs(:resolve).returns({
      agent_runtime: "claude_code",
      mode: "non_interactive",
      tool_ids: [],
      skill_ids: [],
      mcp_server_ids: [],
      repository_ids: [],
      input_asset_ids: []
    })

    session = SessionService.create_for_workflow_step(step_run: step_run)

    assert session.persisted?
    assert_equal "workflow_step", session.session_type
    assert_equal "Do the thing", session.initial_prompt
    assert_equal "running", session.state
    assert_equal session, step_run.reload.terminal_session
    assert_not_nil session.temporal_workflow_id
  end

  private

  def mock_temporal_start
    TemporalService.stubs(:start_workflow).returns({
      ok: true,
      workflow_id: "temporal-wf-#{SecureRandom.hex(4)}",
      run_id: "temporal-run-#{SecureRandom.hex(4)}"
    })
  end
end
