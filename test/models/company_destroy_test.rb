# frozen_string_literal: true

require "test_helper"

# Deleting a company removes everything that references it — sessions, agent
# credentials, Azure installations — and leaves no row behind that nothing can reach.
class CompanyDestroyTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  def wire_up
    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow)
    create(:sub_step, step: step)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    create(:step_run, workflow_run: run, step: step, terminal_session: session)
    create(:session_log, terminal_session: session)
    tool = create(:tool, scope: @project)
    create(:tool_result, tool: tool, terminal_session: session)
    create(:terminal_session, :auth_setup, user: @user, project: nil, company: @company)
    create(:skill, scope: @project)
    create(:agent, scope: @project)
    create(:config_item, scope: @project)
    create(:mcp_server, scope: @project)
    integration = create(:integration, company: @company, connected_by: @user)
    create(:repository, scope: @project, integration: integration)
    create(:asset, scope: @company, created_by: @user)
    create(:asset, scope: @project, created_by: @user)
    create(:folder, scope: @company, path: "shared", created_by: @user)
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    create(:trigger_event, company: @company, project: @project)
    board = create(:board, project: @project)
    create(:board_task, board: board, board_column: create(:board_column, board: board))
    SessionConcurrencyLimit.create!(scope_type: "Company", scope_id: @company.id, max_sessions: 3)
    SessionConcurrencyLimit.create!(scope_type: "Project", scope_id: @project.id, max_sessions: 1)
  end

  test "destroying a company removes everything it owns" do
    wire_up

    @company.destroy!

    assert_not Company.exists?(@company.id)
    [ TerminalSession, AgentCredential, TriggerEvent, Integration ].each do |model|
      assert_not model.exists?(company_id: @company.id), "#{model.name} rows left behind"
    end
    [ Tool, Skill, Agent, ConfigItem, MCPServer, Repository, Asset, Folder, Workflow, SessionConcurrencyLimit ].each do |model|
      assert_not model.unscoped.exists?(company_id: @company.id), "#{model.name} rows left behind"
    end
    assert User.exists?(@user.id), "people are not the company's to delete"
  end

  test "a company whose session runtime is still being torn down refuses to go, and says why" do
    with_company_limit(@company, 1)
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    admission = SessionAdmissionService.enqueue!(session)

    assert_not @company.destroy
    assert_match(/being cleaned up/, @company.errors.full_messages.to_sentence)
    assert Company.exists?(@company.id)
    assert_nil admission.reload.released_at
  end

  test "destroying a project takes its concurrency limit with it" do
    SessionConcurrencyLimit.create!(scope_type: "Project", scope_id: @project.id, max_sessions: 1)

    @project.destroy!

    assert_not SessionConcurrencyLimit.exists?(scope_id: @project.id)
  end
end
