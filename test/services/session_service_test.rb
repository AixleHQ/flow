# frozen_string_literal: true

require "test_helper"

class SessionServiceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
  end

  # == suspended companies ==
  #
  # A suspended or archived company runs nothing. Billing::CapacityWindow bills
  # only active companies, which is only honest while they are also the only ones
  # that can occupy a slot.

  test "create_and_start refuses a session for a suspended company" do
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    @company.update_column(:state, "suspended")

    error = assert_raises(SessionAdmissionService::Stopped) do
      SessionService.create_and_start(
        user: @user, project: @project, session_type: "agent_session", agent_type: "claude_code"
      )
    end

    assert_match(/suspended and cannot run sessions/, error.message)
    assert_equal 0, TerminalSession.count, "nothing may be created for a company that cannot run it"
  end

  test "create_and_start refuses a session for an archived company" do
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    @company.update_column(:state, "archived")

    assert_raises(SessionAdmissionService::Stopped) do
      SessionService.create_and_start(
        user: @user, project: @project, session_type: "agent_session", agent_type: "claude_code"
      )
    end
  end

  # The company can be suspended while a session is already queued or running, so
  # the gate has to be on the recurring check too, not only on creation.
  test "revalidate_admission! stops a session whose company was suspended" do
    session = create(:terminal_session, user: @user, project: @project)
    @company.update_column(:state, "suspended")

    error = assert_raises(SessionAdmissionService::Stopped) do
      SessionService.revalidate_admission!(session)
    end

    assert_match(/cannot run sessions/, error.message)
  end

  test "revalidate_admission! lets an active company through" do
    session = create(:terminal_session, user: @user, project: @project)

    assert_nothing_raised { SessionService.revalidate_admission!(session) }
  end

  # A project-less auth_setup session names its company explicitly, and is gated
  # on the same rule.
  test "create_and_start refuses a project-less session for a suspended company" do
    @company.update_column(:state, "suspended")

    assert_raises(SessionAdmissionService::Stopped) do
      SessionService.create_and_start(
        user: @user, company: @company, session_type: "auth_setup", agent_type: "claude_code"
      )
    end
  end

  # == create_and_start ==

  test "create_and_start admits the session and starts its container workflow" do
    mock_temporal_start
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")

    session = SessionService.create_and_start(
      user: @user,
      project: @project,
      session_type: "agent_session",
      agent_type: "claude_code"
    )

    assert session.persisted?
    assert_equal "acknowledged", session.session_admission.launch_state
    assert_equal "agent_session", session.session_type
    assert_equal "claude_code", session.agent_type
    assert_equal @project.id, session.project_id
    assert_not_nil session.reload.temporal_workflow_id
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
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
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
      user: @user, company: @user.companies.first, session_type: "auth_setup", agent_type: "claude_code",
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
    # A credential that broke on refresh names its server like any other refusal;
    # this raise site used to omit the name and leave the message anonymous.
    assert_equal "Connect required before launching: #{server.name}", error.message
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
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
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
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
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

  # Task #324: Antigravity CLI, asked for a model the account lacks, quietly ran its default
  # model; the step said nothing about it.
  test "create_and_start refuses a model the account's live catalogue does not offer, on a CLI that would run another" do
    AgentCredential.from_artifacts(@user.id, @company.id, "antigravity_cli",
                                   { "access_token" => "at", "auth_method" => "consumer" })
    stub_request(:post, Antigravity::Api::MODELS_URL).to_return(status: 200, body: {
      models: { "gemini-3.8-flash-high" => { displayName: "Gemini 3.8 Flash (High)" } },
      agentModelSorts: [ { groups: [ { modelIds: [ "gemini-3.8-flash-high" ] } ] } ]
    }.to_json)

    error = assert_raises(AgentCredential::ModelUnavailable) do
      SessionService.create_and_start(user: @user, project: @project, session_type: "agent_session",
                                       agent_type: "antigravity_cli", params: { requested_model: "gemini-3.7-flash-high" })
    end

    assert_equal "Antigravity CLI does not offer the model gemini-3.7-flash-high on this account " \
                 "(it offers gemini-3.8-flash-high). Choose another model.", error.message
    assert_kind_of AgentCredential::PreflightError, error
    assert_equal 0, @user.terminal_sessions.count
  end

  # A fallback list says nothing about the account, and an unreachable catalogue must not
  # stop a launch.
  test "create_and_start does not hold a model against a catalogue the vendor did not answer" do
    mock_temporal_start
    AgentCredential.from_artifacts(@user.id, @company.id, "antigravity_cli",
                                   { "access_token" => "at", "auth_method" => "consumer" })
    stub_request(:post, Antigravity::Api::MODELS_URL).to_return(status: 403, body: "{}")

    session = SessionService.create_and_start(user: @user, project: @project, session_type: "agent_session",
                                              agent_type: "antigravity_cli", params: { requested_model: "gemini-3.7-flash-high" })

    assert session.persisted?
  end

  # The production shape (2026-09-17): a token that died while a live session pinned it
  # out of the refresh sweep. The row is still `active` — no refresh was ever attempted,
  # so nothing recorded an error — and the container it would launch could only print
  # "Login expired" until the no-output watchdog reaped it half an hour later.
  test "create_and_start blocks launch when an expired login is pinned by a live session" do
    claude_config = { "claudeAiOauth" => { "accessToken" => "tok",
                                           "refreshToken" => "rt",
                                           "expiresAt" => (1.minute.ago.to_f * 1000).to_i } }
    cred = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", claude_config)
    assert cred.active?
    create(:terminal_session, user: @user, company_id: @company.id,
                              agent_type: "claude_code", state: "ready")

    assert_raises(AgentCredential::PreflightError) do
      SessionService.create_and_start(
        user: @user, project: @project, session_type: "agent_session",
        agent_type: "claude_code", params: {}
      )
    end

    assert_equal 1, @user.terminal_sessions.count, "only the pre-existing session may exist"
  end

  test "create_and_start allows an expired login nothing else is holding (launch refreshes it)" do
    mock_temporal_start
    claude_config = { "claudeAiOauth" => { "accessToken" => "tok",
                                           "refreshToken" => "rt",
                                           "expiresAt" => (1.minute.ago.to_f * 1000).to_i } }
    AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", claude_config)

    session = SessionService.create_and_start(
      user: @user, project: @project, session_type: "agent_session",
      agent_type: "claude_code", params: {}
    )

    assert session.persisted?
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

  test "create_and_start refuses a member with no agent credentials and asks them to connect one" do
    error = assert_raises(AgentCredential::PreflightError) do
      SessionService.create_and_start(
        user: @user, project: @project, session_type: "agent_session",
        agent_type: "claude_code", params: {}
      )
    end

    assert_equal "No agent credentials. Connect an agent in Profile settings to run workflows.", error.message
    assert_equal 0, @user.terminal_sessions.count
  end

  test "create_and_start names the one agent missing when the member has another" do
    create(:agent_credential, user: @user, company: @company, agent_type: "codex")

    error = assert_raises(AgentCredential::PreflightError) do
      SessionService.create_and_start(
        user: @user, project: @project, session_type: "agent_session", agent_type: "claude_code"
      )
    end

    assert_equal "No Claude Code login. Connect it in Profile settings to run this.", error.message
  end

  test "create_and_start counts only this company's credentials" do
    other = create(:company_membership, user: @user)
    create(:agent_credential, user: @user, company: other.company, agent_type: "claude_code")

    error = assert_raises(AgentCredential::PreflightError) do
      SessionService.create_and_start(
        user: @user, project: @project, session_type: "agent_session", agent_type: "claude_code"
      )
    end

    assert_equal AgentCredential::PreflightError::NO_CREDENTIALS, error.message
  end

  test "an auth_setup session starts with no agent credentials, since it is how one gets connected" do
    mock_temporal_start

    session = SessionService.create_and_start(
      user: @user, company: @company, session_type: "auth_setup", agent_type: "claude_code"
    )

    assert session.persisted?
  end

  test "a workflow step without any agent credential fails before a session is built" do
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    step_run = create(:step_run, workflow_run: run, step: create(:step, workflow: workflow))

    error = assert_raises(AgentCredential::PreflightError) { SessionService.build_for_workflow_step(step_run: step_run) }

    assert_equal AgentCredential::PreflightError::NO_CREDENTIALS, error.message
    assert_equal 0, TerminalSession.count
  end

  test "create_and_start launches when the OAuth MCP server is connected for the user" do
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
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
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
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

  # == suspend and restore (Sessions::Suspension) ==

  include CheckpointStorageHelper

  def interactive_session(**attrs)
    create(:terminal_session, :running, :agent_session, user: @user, project: @project, mode: "interactive",
                                                        state: "ready", temporal_workflow_id: "wf-1", **attrs)
  end

  test "restore starts a session that continues the suspended one with its configuration" do
    use_checkpoint_storage
    mock_temporal_start
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    skill = create(:skill, scope: @project)
    origin = interactive_session(skill_ids: [ skill.id ])
    Sessions::Lifecycle.suspended(origin)
    create_checkpoint(origin)

    restored = SessionService.restore(session: origin, user: @user)

    assert restored.persisted?
    assert_equal origin.id, restored.restored_from_session_id
    assert_equal [ skill.id ], restored.skill_ids
    assert_equal "interactive", restored.mode
    assert_equal restored, SessionService.restore(session: origin, user: @user), "a restore on its way is not started twice"
  ensure
    restore_checkpoint_storage
  end

  test "only the owner can restore a suspended session" do
    use_checkpoint_storage
    origin = interactive_session
    Sessions::Lifecycle.suspended(origin)
    create_checkpoint(origin)
    stranger = create(:user, :with_company)

    assert_raises(TerminalSession::InvalidStateError) { SessionService.restore(session: origin, user: stranger) }
  ensure
    restore_checkpoint_storage
  end

  # == suspended workflow steps ==

  def suspended_step(run_state: "running")
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user, state: run_state)
    step_run = create(:step_run, workflow_run: run, step: create(:step, workflow: workflow), state: "running")
    origin = create(:terminal_session, :running, user: @user, project: @project, session_type: "workflow_step",
                                                 mode: "interactive", state: "ready", temporal_workflow_id: "wf-step",
                                                 metadata: { "step_run_id" => step_run.id })
    step_run.update!(terminal_session: origin)
    Sessions::Lifecycle.suspended(origin)
    create_checkpoint(origin)
    [ origin.reload, step_run.reload ]
  end

  test "suspending a workflow step marks the step suspended for its run to wait on" do
    use_checkpoint_storage
    origin, step_run = suspended_step

    assert_equal "suspended", step_run.state
    assert origin.suspended?
    assert Sessions::Suspension.restorable?(origin)
  ensure
    restore_checkpoint_storage
  end

  # The run reads the step's current session, so the restored one has to become it.
  test "restoring a step builds its next session on the same step run, which the run then waits on" do
    use_checkpoint_storage
    mock_temporal_start
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    origin, step_run = suspended_step

    restored = SessionService.restore(session: origin, user: @user)

    step_run.reload
    assert_equal "workflow_step", restored.session_type
    assert_equal origin.id, restored.restored_from_session_id
    assert_equal restored.id, step_run.terminal_session_id
    assert_equal "running", step_run.state
    assert_equal [ restored.id, origin.id ], step_run.session_history.map(&:id)
    assert_equal step_run, origin.reload.owning_step_run, "the earlier session still knows its step"
    assert_equal restored, SessionService.restore(session: origin, user: @user), "a restore on its way is not started twice"
  ensure
    restore_checkpoint_storage
  end

  # The set is the suspended session's, not what the step's workflow links by now.
  test "restoring a step keeps the suspended session's integrations, whatever the workflow links since" do
    use_checkpoint_storage
    mock_temporal_start
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    kept = create(:integration, :coder, :active, company: @company, project: @project)
    detached = create(:integration, :coder, :active, company: @company, project: @project)
    later = create(:integration, :coder, :active, company: @company, project: @project)
    origin, step_run = suspended_step
    origin.integrations = [ kept, detached ]
    step_run.workflow_run.workflow.update!(config: step_run.workflow_run.workflow.config.merge("base_integration_ids" => [ kept.id, later.id ]))

    restored = SessionService.restore(session: origin, user: @user)

    assert_equal [ kept.id, detached.id ].sort, restored.integration_ids.sort
    refute_includes restored.integration_ids, later.id
  ensure
    restore_checkpoint_storage
  end

  test "restoring a step leaves out an integration that is no longer available" do
    use_checkpoint_storage
    mock_temporal_start
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    kept = create(:integration, :coder, :active, company: @company, project: @project)
    gone = create(:integration, :coder, :active, company: @company, project: @project)
    origin, = suspended_step
    origin.integrations = [ kept, gone ]
    gone.update_columns(status: "inactive")

    restored = SessionService.restore(session: origin, user: @user)

    assert_equal [ kept.id ], restored.integration_ids
  ensure
    restore_checkpoint_storage
  end

  test "a step its run no longer waits on cannot be restored" do
    use_checkpoint_storage
    origin, step_run = suspended_step
    step_run.mark_skipped!("Skipped by user")

    refute Sessions::Suspension.restorable?(origin.reload)
    assert_raises(TerminalSession::InvalidStateError) { SessionService.restore(session: origin, user: @user) }
  ensure
    restore_checkpoint_storage
  end

  # A run lasts TemporalWorkflowRegistry::RUN_TIMEOUT from its start; a step it waits on
  # cannot be restored after the run has given up.
  test "a step's restore window ends before its run does" do
    use_checkpoint_storage
    travel_to(Time.current) do
      workflow = create(:workflow, scope: @project)
      run = create(:workflow_run, workflow: workflow, project: @project, user: @user, state: "running",
                                  created_at: 35.days.ago)
      step_run = create(:step_run, workflow_run: run, step: create(:step, workflow: workflow), state: "running")
      origin = create(:terminal_session, :running, user: @user, project: @project, session_type: "workflow_step",
                                                   mode: "interactive", state: "ready")
      step_run.update!(terminal_session: origin)

      Sessions::Lifecycle.suspended(origin)

      assert_equal run.created_at + TemporalWorkflowRegistry::RUN_TIMEOUT.seconds - 12.hours, origin.reload.restore_expires_at
    end
  ensure
    restore_checkpoint_storage
  end

  # == create_for_workflow_step ==

  test "create_for_workflow_step refuses a step model the Grok account does not offer, before any container" do
    login = { Agents::GrokAdapter::OAUTH_SCOPE => { "key" => "session", "token_type" => "Bearer" } }.to_json
    create(:agent_credential, user: @user, company: @company, agent_type: "grok",
                              config_data: AgentCredentialsService.for("grok").adapter.extract_credentials(login))
    stub_request(:get, Grok::Api::MODELS_URL).to_return(status: 200, body: { data: [ { id: "grok-4.7" } ] }.to_json)
    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow, required_agent_runtime: "grok", preferred_model: "grok-4.6")
    step_run = create(:step_run, workflow_run: create(:workflow_run, workflow: workflow, project: @project, user: @user), step: step)

    error = assert_raises(AgentCredential::ModelUnavailable) { SessionService.create_for_workflow_step(step_run: step_run) }

    assert_equal "Grok does not offer the model grok-4.6 on this account (it offers grok-4.7). Choose another model.", error.message
    assert_equal 0, TerminalSession.where(user: @user).count
  end

  test "create_for_workflow_step creates session bound to step_run" do
    mock_temporal_start
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")

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
    assert_equal "acknowledged", session.session_admission.launch_state
    assert_equal session, step_run.reload.terminal_session
    assert_not_nil session.reload.temporal_workflow_id
  end

  test "create_for_workflow_step attaches step assets to session input_assets" do
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
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

  test "create_for_workflow_step builds the session before it takes the admission writer lock" do
    mock_temporal_start
    step_run = workflow_step_run
    statements = []
    record = ->(*, payload) { statements << payload[:sql] }

    ActiveSupport::Notifications.subscribed(record, "sql.active_record") do
      SessionService.create_for_workflow_step(step_run: step_run)
    end

    insert = statements.index { |sql| sql.start_with?('INSERT INTO "terminal_sessions"') }
    writer_lock = statements.index { |sql| sql.include?('FROM "session_admission_policies"') && sql.include?("FOR UPDATE") }
    assert_operator insert, :<, writer_lock, "the session must be built before the installation-wide lock is taken"
  end

  test "a retried launch queues the session an earlier attempt built but never admitted" do
    mock_temporal_start
    step_run = workflow_step_run
    built = SessionService.build_for_workflow_step(step_run: step_run)

    session = assert_no_difference(-> { TerminalSession.count }) do
      SessionService.create_for_workflow_step(step_run: step_run)
    end

    assert_equal built, session
    assert session.session_admission.present?
  end

  test "a step's session carries its step's reasoning effort" do
    step_run = workflow_step_run(required_agent_runtime: "claude_code", preferred_model: "claude-opus-5",
                                 reasoning_effort: "high")

    assert_equal "high", SessionService.build_for_workflow_step(step_run: step_run).reasoning_effort
  end

  test "a step session's generated config keeps the model and level it captured when the step changes after queueing" do
    create(:agent_credential, user: @user, company: @company, agent_type: "gemini_cli")
    step_run = workflow_step_run(required_agent_runtime: "gemini_cli", preferred_model: "gemini-3-pro",
                                 reasoning_effort: "low")
    session = SessionService.build_for_workflow_step(step_run: step_run)

    step_run.step.update!(preferred_model: "gemini-2.5-pro", reasoning_effort: nil)

    session.reload
    assembly = SessionContextService.new("ctr1", session, runtime: ContainerRuntime.for_session(session))
    config = assembly.credential_workflow_config(nil, [])
    assert_equal "gemini-3-pro", config[:model]
    assert_equal "low", config[:reasoning_effort]
  end

  test "a step without a reasoning effort leaves its session on the CLI's default" do
    assert_nil SessionService.build_for_workflow_step(step_run: workflow_step_run).reasoning_effort
  end

  test "a run stopped after its step session was built cancels that session instead of queueing it" do
    step_run = workflow_step_run
    built = SessionService.build_for_workflow_step(step_run: step_run)
    step_run.workflow_run.update!(stop_requested_at: Time.current)

    assert_raises(SessionAdmissionService::Stopped) { SessionService.create_for_workflow_step(step_run: step_run) }

    assert_equal "cancelled", built.reload.state
    assert_nil built.session_admission
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
    OauthCredential.create!(owner: @user, oauth_client: client, mcp_server: server,
                                   provider: "mcp:y", status: :active,
                                   access_token: "tok2", expires_at: 2.hours.from_now,
                                   refresh_token: "rt-xyz")

    # Token has > PRE_START_SKEW remaining — refresh_if_expiring_soon must not call fresh (no HTTP).
    Oauth::TokenService.expects(:fresh).never

    SessionService.send(:preflight_oauth!, @user, [ server.id ])
  end

  private

  def workflow_step_run(**step_attributes)
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow, instructions: "Do the thing", **step_attributes)
    workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    create(:step_run, workflow_run: workflow_run, step: step)
  end
end
