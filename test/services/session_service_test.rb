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

  test "create_and_start records auth_kind in the session metadata (design-login)" do
    mock_temporal_start

    session = SessionService.create_and_start(
      user: @user, session_type: "auth_setup", agent_type: "claude_code",
      params: { auth_kind: "design", mode: "interactive" }
    )

    assert session.persisted?
    assert_equal "design", session.metadata["auth_kind"]
  end

  # == create_and_start: OAuth session-start preflight (§4.6) ==

  test "create_and_start blocks launch when an OAuth MCP server has no usable credential" do
    server = create(:mcp_server, :custom, scope: @project, transport: :sse,
                    auth_type: :oauth, credential_scope: :per_user)

    error = assert_raises(Oauth::PreflightError) do
      SessionService.create_and_start(
        user: @user, project: @project, session_type: "agent_session",
        agent_type: "claude_code", params: { mcp_server_ids: [ server.id ] }
      )
    end

    assert_equal 1, error.connections.size
    assert_equal server.id, error.connections.first[:mcp_server_id]
    assert_equal 0, @user.terminal_sessions.count, "must not create a session it can't launch"
  end

  test "create_and_start launches when the OAuth MCP server is connected for the user" do
    mock_temporal_start
    server = create(:mcp_server, :custom, scope: @project, transport: :sse,
                    auth_type: :oauth, credential_scope: :per_user)
    client = OauthClient.create!(
      issuer: "https://provider.test", authorization_endpoint: "https://provider.test/a",
      token_endpoint: "https://provider.test/t", client_id: "c1", source: "static"
    )
    OauthCredential.create!(owner: @user, oauth_client: client, mcp_server: server, provider: "mcp:x",
                            status: :active, access_token: "tok", expires_at: 1.hour.from_now)

    session = SessionService.create_and_start(
      user: @user, project: @project, session_type: "agent_session",
      agent_type: "claude_code", params: { mcp_server_ids: [ server.id ] }
    )

    assert session.persisted?
    assert_includes session.mcp_server_ids, server.id
  end

  # == finish ==

  test "finish transitions session to finishing and sends container_finished signal" do
    session = create(:terminal_session, :running, user: @user, temporal_workflow_id: "wf-123")

    TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, nil).once

    SessionService.finish(session: session)

    session.reload
    assert_equal "finishing", session.state
    assert_not_nil session.finishing_at
  end

  test "finish is idempotent across repeated calls on a running session" do
    session = create(:terminal_session, :running, user: @user, temporal_workflow_id: "wf-123")

    # A duplicate user click (or simultaneous web + mobile invocations) must
    # send the container_finished signal exactly once — extra signals would
    # cause double cleanup on the Temporal worker side.
    TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, nil).once

    SessionService.finish(session: session)
    session.reload
    first_finishing_at = session.finishing_at

    SessionService.finish(session: session)
    session.reload

    assert_equal "finishing", session.state
    assert_equal first_finishing_at.to_i, session.finishing_at.to_i
  end

  test "finish is a no-op when session is already finishing" do
    session = create(:terminal_session, :finishing, user: @user, temporal_workflow_id: "wf-123")
    original_finishing_at = session.finishing_at

    TemporalService.expects(:send_signal).never

    SessionService.finish(session: session)

    session.reload
    assert_equal "finishing", session.state
    assert_equal original_finishing_at.to_i, session.finishing_at.to_i
  end

  test "finish signals container workflow for workflow_step sessions" do
    workflow_run = create(:workflow_run, project: @project, user: @user)
    step = create(:step, workflow: workflow_run.workflow)
    step_run = create(:step_run, workflow_run: workflow_run, step: step)
    session = create(:terminal_session, :running, user: @user, session_type: "workflow_step",
                     temporal_workflow_id: "wf-456", project: @project)
    step_run.update!(terminal_session: session)

    # Only signals the container workflow; execution workflow is notified by before_cleanup
    TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, step_run.id).once

    SessionService.finish(session: session)

    session.reload
    assert_equal "finishing", session.state
  end

  test "finish raises InvalidStateError for non-finishable session" do
    session = create(:terminal_session, user: @user, state: "finished")

    assert_raises(TerminalSession::InvalidStateError) do
      SessionService.finish(session: session)
    end
  end

  test "finish without temporal workflow transitions through finishing to finished" do
    session = create(:terminal_session, :running, user: @user, temporal_workflow_id: nil)

    SessionService.finish(session: session)

    session.reload
    assert_equal "finished", session.state
    assert_not_nil session.finishing_at
    assert_not_nil session.finished_at
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

  test "create_for_workflow_step attaches step assets to session input_assets" do
    mock_temporal_start

    asset = create(:asset, scope: @project, created_by: @user, name: "step-doc.md")
    workflow = create(:workflow, scope: @company)
    step = create(:step, workflow: workflow, instructions: "Use the doc", asset_ids: [ asset.id ])
    workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    step_run = create(:step_run, workflow_run: workflow_run, step: step)

    session = SessionService.create_for_workflow_step(step_run: step_run)

    # SessionContextService#inject_assets mounts session.input_asset_ids into the container,
    # so a step asset reaching session.input_assets is the contract that it reaches /workspace/assets/.
    assert_includes session.input_assets, asset
  end
end
