# frozen_string_literal: true

require "test_helper"

# Page render-smoke: the project-scoped WorkflowRuns controller renders
# Projects/WorkflowRuns/ShowPage (#show); #index now redirects into the unified
# Sessions & Runs list. Happy-path render contract, complementing
# workflow_runs_authorization_test.rb (permit/forbid matrix).
class Web::Company::Projects::WorkflowRunsRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project)
    Bullet.enable = false # eager-loaded collections trip the unused-eager-loading gate
    sign_in_as(@user)
  end

  teardown { Bullet.enable = true }

  test "index redirects to the unified sessions and runs list, filtered to runs" do
    create_list(:workflow_run, 2, workflow: @workflow, project: @project, user: @user)

    get company_project_workflow_runs_path(@project)

    assert_redirected_to company_project_sessions_path(@project, type: "run")
  end

  test "show renders the workflow run page for a run in the project" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)

    get company_project_workflow_run_path(@project, run)

    assert_response :success
    assert_inertia_page "Projects/WorkflowRuns/ShowPage"
    assert_inertia_props do |props|
      props[:run][:id] == run.id
    end
  end

  test "show reports the workflow's description and the run's rolled-up token total" do
    workflow = create(:workflow, scope: @project, description: "Ships the release")
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    step_one = create(:step, workflow: workflow, position: 1)
    step_two = create(:step, workflow: workflow, position: 2)
    session_one = create(:terminal_session, session_type: "workflow_step", project: @project, user: @user,
                                             total_tokens: 100)
    session_two = create(:terminal_session, session_type: "workflow_step", project: @project, user: @user,
                                             total_tokens: 250)
    create(:step_run, workflow_run: run, step: step_one, terminal_session: session_one)
    create(:step_run, workflow_run: run, step: step_two, terminal_session: session_two)

    get company_project_workflow_run_path(@project, run)

    assert_response :success
    assert_inertia_props do |props|
      props[:run][:workflowDescription] == "Ships the release" && props[:run][:totalTokens] == 350
    end
  end

  test "show lists the run's LLM calls, and a live update of the run does not read them" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
    session = create(:terminal_session, session_type: "workflow_step", project: @project, user: @user)
    create(:llm_call, terminal_session: session, workflow_run: run, model: "gpt-6-sol")

    get company_project_workflow_run_path(@project, run)

    assert_inertia_props { |props| props[:llmCalls].pluck(:model) == [ "gpt-6-sol" ] }

    llm_call_queries = count_queries_on("llm_calls") do
      get company_project_workflow_run_path(@project, run),
          headers: { "X-Inertia" => "true", "X-Inertia-Partial-Component" => "Projects/WorkflowRuns/ShowPage",
                     "X-Inertia-Partial-Data" => "run,assets" }
    end
    assert_response :success
    assert_equal 0, llm_call_queries
  end

  private

  def count_queries_on(table)
    count = 0
    counter = lambda do |*, payload|
      count += 1 if payload[:sql].include?(%("#{table}")) && payload[:name] != "SCHEMA"
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end
