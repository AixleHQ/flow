# frozen_string_literal: true

require "test_helper"

# Page render-smoke: the project-scoped Sessions controller renders three
# Inertia pages — Projects/Sessions/SessionsRunsPage (#index, the unified
# sessions-and-runs list), Projects/Sessions/NewPage (#new) and
# Projects/Sessions/ShowPage (#show).
# Happy-path render contract, complementing sessions_authorization_test.rb
# (permit/forbid matrix).
class Web::Company::Projects::SessionsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false # eager-loaded collections trip the unused-eager-loading gate
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "index renders the unified sessions and runs page" do
    session = create(:terminal_session, :agent_session, project: @project, user: @user)

    get company_project_sessions_path(@project)

    assert_response :success
    assert_inertia_page "Projects/Sessions/SessionsRunsPage"
    assert_inertia_props do |props|
      props[:entries].any? { |e| e[:id] == session.id && e[:kind] == "session" }
    end
  end

  test "new renders the new session page" do
    get new_company_project_session_path(@project)

    assert_response :success
    assert_inertia_page "Projects/Sessions/NewPage"
  end

  # Names and types reach the picker; the value never leaves the vault. The whole
  # point of routing values through `get_config_item` is that they are fetched on
  # demand and audited, so a prop carrying one would undo the feature.
  test "new offers the project's config items by name and type, never a value" do
    create(:config_item, :secret, scope: @project, name: "STRIPE_KEY", value: "sk_live_abc123",
                                  description: "Billing key")

    get new_company_project_session_path(@project)

    assert_response :success
    assert_inertia_props do |props|
      offered = props[:configItems]
      offered.present? &&
        offered.map { |c| c[:name] } == [ "STRIPE_KEY" ] &&
        offered.map { |c| c[:itemType] } == [ "secret" ] &&
        offered.map { |c| c[:description] } == [ "Billing key" ]
    end
    assert_not_includes response.body, "sk_live_abc123"
  end

  test "show renders a session" do
    session = create(:terminal_session, :agent_session, project: @project, user: @user)

    get company_project_session_path(@project, session)

    assert_response :success
    assert_inertia_page "Projects/Sessions/ShowPage"
    assert_inertia_props do |props|
      props[:session].present? && props[:session][:id] == session.id
    end
  end

  test "show includes workflow_context for a session that belongs to a workflow step" do
    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow, name: "Draft the plan", position: 2)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    session = create(:terminal_session, session_type: "workflow_step", project: @project, user: @user)
    create(:step_run, workflow_run: run, step: step, terminal_session: session)
    create(:step_run, workflow_run: run, step: create(:step, workflow: workflow, position: 1))

    get company_project_session_path(@project, session)

    assert_response :success
    assert_inertia_props do |props|
      ctx = props[:workflowContext]
      ctx.present? &&
        ctx[:runId] == run.id &&
        ctx[:runName] == workflow.name &&
        ctx[:runPath] == company_project_workflow_run_path(@project, run) &&
        ctx[:stepName] == "Draft the plan" &&
        ctx[:stepPosition] == 2 &&
        ctx[:stepsTotal] == 2
    end
  end

  test "show has a nil workflow_context for a standalone session" do
    session = create(:terminal_session, :agent_session, project: @project, user: @user)

    get company_project_session_path(@project, session)

    assert_response :success
    assert_inertia_props { |props| props[:workflowContext].nil? }
  end

  test "index rolls up a run's step sessions into its list entry" do
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    step_one = create(:step, workflow: workflow, name: "Plan", position: 1)
    step_two = create(:step, workflow: workflow, name: "Build", position: 2)
    session_one = create(:terminal_session, session_type: "workflow_step", project: @project, user: @user,
                                             agent_type: "claude_code", total_tokens: 100, cost_cents: 20,
                                             state: "finished")
    session_two = create(:terminal_session, session_type: "workflow_step", project: @project, user: @user,
                                             agent_type: "codex", total_tokens: 50, cost_cents: 5, state: "finished")
    create(:step_run, :completed, workflow_run: run, step: step_one, terminal_session: session_one)
    create(:step_run, workflow_run: run, step: step_two, terminal_session: session_two)

    get company_project_sessions_path(@project, type: "run")

    assert_response :success
    assert_inertia_props do |props|
      entry = props[:entries].find { |e| e[:id] == run.id && e[:kind] == "run" }
      entry.present? &&
        entry[:agentType] == "claude_code" && # first step by position wins
        entry[:totalTokens] == 150 &&
        entry[:costCents] == 25 &&
        entry[:stepsCompleted] == 1 &&
        entry[:stepsTotal] == 2 &&
        entry[:sessions].map { |s| s[:id] } == [ session_one.id, session_two.id ]
    end
  end
end
