# frozen_string_literal: true

require "test_helper"

class SessionServiceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
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

  test "create_and_start blocks launch when a credential enters error status after a failed pre-start refresh" do
    server = create(:mcp_server, :custom, scope: @project, transport: :sse,
                    auth_type: :oauth, credential_scope: :per_user)
    client = OauthClient.create!(
      issuer: "https://provider.test3", authorization_endpoint: "https://provider.test3/a",
      token_endpoint: "https://provider.test3/t", client_id: "c3", source: "static"
    )
    cred = OauthCredential.create!(owner: @user, oauth_client: client, mcp_server: server,
                                   provider: "mcp:z", status: :active,
                                   access_token: "tok", expires_at: 30.minutes.from_now,
                                   refresh_token: "rt-fail")

    Oauth::TokenService.stubs(:refresh_if_expiring_soon).with(cred) do
      cred.update_columns(status: "error")
    end

    error = assert_raises(Oauth::PreflightError) do
      SessionService.create_and_start(
        user: @user, project: @project, session_type: "agent_session",
        agent_type: "claude_code", params: { mcp_server_ids: [ server.id ] }
      )
    end

    assert_equal 0, @user.terminal_sessions.count, "must not create a session with a broken credential"
    assert_equal "/oauth/mcp/#{server.id}/connect", error.connections.first[:connect_url]
  end

  test "create_and_start blocks launch when a credential is already in error status before start" do
    server = create(:mcp_server, :custom, scope: @project, transport: :sse,
                    auth_type: :oauth, credential_scope: :per_user)
    client = OauthClient.create!(
      issuer: "https://provider.test4", authorization_endpoint: "https://provider.test4/a",
      token_endpoint: "https://provider.test4/t", client_id: "c4", source: "static"
    )
    OauthCredential.create!(owner: @user, oauth_client: client, mcp_server: server,
                            provider: "mcp:q", status: :error,
                            access_token: "tok", expires_at: 30.minutes.from_now,
                            refresh_token: "rt-ok")

    error = assert_raises(Oauth::PreflightError) do
      SessionService.create_and_start(
        user: @user, project: @project, session_type: "agent_session",
        agent_type: "claude_code", params: { mcp_server_ids: [ server.id ] }
      )
    end

    assert_equal "/oauth/mcp/#{server.id}/connect", error.connections.first[:connect_url]
  end

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

  # == create_and_start: cloud-connection preflight ==
  #
  # A credential source inside the container cannot talk to the user and Claude Code
  # hides Bedrock errors, so a rotten connection has to be caught before launch or the
  # session simply never answers.

  test "create_and_start blocks launch when the user's AWS connection has rotted" do
    AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", {
      "awsBedrock" => {
        "region" => "us-east-1", "profile" => "aixle-bedrock",
        "credential_process" => "/usr/local/bin/aixle-aws-creds",
        "identity_center" => {
          "account_id" => "111122223333", "role_name" => "BedrockUser", "sso_region" => "us-west-2",
          # Registrations die at 90 days and refresh cannot cross that boundary.
          "registration" => { "client_id" => "c", "expires_at" => 1.day.ago.iso8601 },
          "token" => { "access_token" => "t", "refresh_token" => "r", "expires_at" => 1.hour.from_now.iso8601 }
        }
      }
    })

    error = assert_raises(CloudAuth::PreflightError) do
      SessionService.create_and_start(
        user: @user, project: @project, session_type: "agent_session", agent_type: "claude_code"
      )
    end

    assert_equal 1, error.connections.size
    assert_equal "registration_expired", error.connections.first[:reason]
    assert_equal CloudAuth::Preflight::CONNECT_PATH, error.connections.first[:connect_url]
    assert_equal 0, @user.terminal_sessions.count, "must not create a session it can't launch"
  end

  test "create_and_start launches for a user with a healthy AWS connection" do
    mock_temporal_start
    AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", {
      "awsBedrock" => {
        "region" => "us-east-1", "profile" => "aixle-bedrock",
        "credential_process" => "/usr/local/bin/aixle-aws-creds",
        "identity_center" => {
          "account_id" => "111122223333", "role_name" => "BedrockUser", "sso_region" => "us-west-2",
          "registration" => { "client_id" => "c", "expires_at" => 60.days.from_now.iso8601 },
          "token" => { "access_token" => "t", "refresh_token" => "r", "expires_at" => 1.hour.from_now.iso8601 }
        }
      }
    })

    session = SessionService.create_and_start(
      user: @user, project: @project, session_type: "agent_session", agent_type: "claude_code"
    )

    assert session.persisted?
  end

  # The preflight checks the connection of the company being billed — the project's.
  # A consultant's rotten connection in another company is that company's problem.
  test "create_and_start ignores a rotten AWS connection in another company" do
    mock_temporal_start
    other_company = create(:company)
    create(:company_membership, user: @user, company: other_company)
    AgentCredential.from_artifacts(@user.id, other_company.id, "claude_code", {
      "awsBedrock" => {
        "region" => "us-east-1", "profile" => "aixle-bedrock",
        "credential_process" => "/usr/local/bin/aixle-aws-creds",
        "identity_center" => {
          "account_id" => "111122223333", "role_name" => "BedrockUser", "sso_region" => "us-west-2",
          "registration" => { "client_id" => "c", "expires_at" => 1.day.ago.iso8601 },
          "token" => { "access_token" => "t", "refresh_token" => "r", "expires_at" => 1.hour.from_now.iso8601 }
        }
      }
    })

    session = SessionService.create_and_start(
      user: @user, project: @project, session_type: "agent_session", agent_type: "claude_code"
    )

    assert session.persisted?
  end

  # Not using Bedrock must never be treated as a broken connection.
  test "create_and_start launches for a user with no cloud connection at all" do
    mock_temporal_start

    session = SessionService.create_and_start(
      user: @user, project: @project, session_type: "agent_session", agent_type: "claude_code"
    )

    assert session.persisted?
  end

  # == create_and_start: agent credential preflight ==

  test "create_and_start blocks launch when agent credential is in error status" do
    cred = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", { "primaryApiKey" => "sk-test" })
    cred.mark_refresh_error!("invalid_grant", permanent: true)

    error = assert_raises(AgentCredential::PreflightError) do
      SessionService.create_and_start(
        user: @user, project: @project, session_type: "agent_session",
        agent_type: "claude_code", params: {}
      )
    end

    assert_includes error.message, "expired"
    assert_equal 0, @user.terminal_sessions.count
  end

  # The catch-22 this guards: the refresh sweep marks a credential broken, and the
  # only flow that can replace it is an auth_setup session — so gating that session
  # on the same credential locks the user out for good.
  test "create_and_start lets an auth_setup session run on a credential in error status" do
    mock_temporal_start
    cred = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", { "primaryApiKey" => "sk-test" })
    cred.mark_refresh_error!("invalid_grant", permanent: true)

    session = SessionService.create_and_start(
      user: @user, company: @company, session_type: "auth_setup",
      agent_type: "claude_code", params: {}
    )

    assert session.persisted?, "re-authentication must not be gated on the credential it replaces"
  end

  test "create_and_start proceeds when agent credential is active" do
    mock_temporal_start
    AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", { "primaryApiKey" => "sk-test" })

    session = SessionService.create_and_start(
      user: @user, project: @project, session_type: "agent_session",
      agent_type: "claude_code", params: {}
    )

    assert session.persisted?
  end

  test "create_and_start proceeds when no agent credential exists" do
    mock_temporal_start

    session = SessionService.create_and_start(
      user: @user, project: @project, session_type: "agent_session",
      agent_type: "claude_code", params: {}
    )

    assert session.persisted?
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

  test "create_and_start blocks launch when a selected MCP server URL is unsafe at launch time (F34)" do
    # Server was valid at creation; simulate its URL becoming unsafe since then
    # (DNS rebinding / edited row) by saving past validation, then failing the
    # launch-time re-check.
    server = build(:mcp_server, :custom, scope: @project, transport: :sse, url: "https://mcp.example.com")
    server.save!(validate: false)
    UrlSafetyValidator.stubs(:errors_for).returns([ "cannot point to private or internal network addresses" ])

    error = assert_raises(SessionService::UnsafeMcpUrlError) do
      SessionService.create_and_start(
        user: @user, project: @project, session_type: "agent_session",
        agent_type: "claude_code", params: { mcp_server_ids: [ server.id ] }
      )
    end
    assert_match(/#{Regexp.escape(server.name)}/, error.message)
    assert_nil @user.terminal_sessions.last, "session must not be created when a selected MCP URL is unsafe"
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

  # == fail_session ==

  test "fail_session records the error, fails the session and signals its container workflow" do
    session = create(:terminal_session, :running, user: @user, temporal_workflow_id: "wf-dead")

    # The container workflow ("agent-session-<id>") is the execution that owns the
    # pod: without this signal it waits out its 23-hour `container_finished`
    # timeout, its cleanup phase never runs, and the pod, Service, IngressRoute and
    # Middlewares leak for a day.
    TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, nil).once

    SessionService.fail_session(session: session, error_message: "Agent container vanished")

    session.reload
    assert_equal "failed", session.state
    assert_equal "Agent container vanished", session.error_message
    assert_not_nil session.finished_at
  end

  test "fail_session signals the container workflow as well as the parent workflow run" do
    workflow_run = create(:workflow_run, project: @project, user: @user)
    step = create(:step, workflow: workflow_run.workflow)
    step_run = create(:step_run, workflow_run: workflow_run, step: step)
    session = create(:terminal_session, :running, user: @user, session_type: "workflow_step",
                     project: @project, temporal_workflow_id: "wf-step")
    step_run.update!(terminal_session: session)

    # TerminalSession#on_failed only reaches the parent run, which completes the
    # step. That is not enough on its own — both executions must hear about it.
    TemporalService.expects(:send_signal)
      .with("workflow-execution-#{workflow_run.id}", :container_finished, step_run.id).once
    TemporalService.expects(:send_signal)
      .with(session.workflow_id, :container_finished, step_run.id).once

    SessionService.fail_session(session: session, error_message: "Agent container vanished")

    assert_equal "failed", session.reload.state
  end

  test "fail_session fails a session that has no temporal workflow without signalling" do
    session = create(:terminal_session, :running, user: @user, temporal_workflow_id: nil)

    TemporalService.expects(:send_signal).never

    SessionService.fail_session(session: session, error_message: "Agent container vanished")

    session.reload
    assert_equal "failed", session.state
    assert_equal "Agent container vanished", session.error_message
  end

  test "fail_session on an already failed session keeps its original error and still signals" do
    session = create(:terminal_session, :failed, user: @user, temporal_workflow_id: "wf-dead")

    # A second sweep must still be able to nudge a container workflow that is
    # somehow still running — the state transition is what is idempotent here.
    TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, nil).once

    SessionService.fail_session(session: session)

    session.reload
    assert_equal "failed", session.state
    assert_equal "Container failed to start", session.error_message
  end

  # == create_for_workflow_step ==

  test "create_for_workflow_step creates session bound to step_run" do
    mock_temporal_start

    workflow = create(:workflow, scope: @project)
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
    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow, instructions: "Use the doc", asset_ids: [ asset.id ])
    workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    step_run = create(:step_run, workflow_run: workflow_run, step: step)

    session = SessionService.create_for_workflow_step(step_run: step_run)

    # SessionContextService#inject_assets mounts session.input_asset_ids into the container,
    # so a step asset reaching session.input_assets is the contract that it reaches /workspace/assets/.
    assert_includes session.input_assets, asset
  end

  # == preflight_oauth! with near-expiry token refresh ==

  test "preflight_oauth! calls refresh_if_expiring_soon for a token expiring within PRE_START_SKEW" do
    server = create(:mcp_server, :custom, scope: @project, transport: :sse,
                    auth_type: :oauth, credential_scope: :per_user)
    client = OauthClient.create!(
      issuer: "https://provider.test", authorization_endpoint: "https://provider.test/a",
      token_endpoint: "https://provider.test/t", client_id: "c1", source: "static"
    )
    cred = OauthCredential.create!(owner: @user, oauth_client: client, mcp_server: server,
                                   provider: "mcp:x", status: :active,
                                   access_token: "tok", expires_at: 30.minutes.from_now,
                                   refresh_token: "rt-abc")

    Oauth::TokenService.expects(:refresh_if_expiring_soon).with(cred).once

    SessionService.send(:preflight_oauth!, @user, [ server.id ])
  end

  test "preflight_oauth! does not refresh a token with more than PRE_START_SKEW remaining" do
    server = create(:mcp_server, :custom, scope: @project, transport: :sse,
                    auth_type: :oauth, credential_scope: :per_user)
    client = OauthClient.create!(
      issuer: "https://provider.test2", authorization_endpoint: "https://provider.test2/a",
      token_endpoint: "https://provider.test2/t", client_id: "c2", source: "static"
    )
    cred = OauthCredential.create!(owner: @user, oauth_client: client, mcp_server: server,
                                   provider: "mcp:y", status: :active,
                                   access_token: "tok2", expires_at: 2.hours.from_now,
                                   refresh_token: "rt-xyz")

    # Token has > PRE_START_SKEW remaining — refresh_if_expiring_soon must not call fresh (no HTTP).
    Oauth::TokenService.expects(:fresh).never

    SessionService.send(:preflight_oauth!, @user, [ server.id ])
  end
end
