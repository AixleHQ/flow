# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::WorkflowRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project)
    sign_in_as(@user)
  end

  test "index renders workflow runs page" do
    create_list(:workflow_run, 2, workflow: @workflow, project: @project, user: @user)

    get company_project_workflow_runs_path(@project)
    assert_inertia_page "Projects/WorkflowRuns/WorkflowRunsPage"
  end

  test "show renders workflow run page" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)

    get company_project_workflow_run_path(@project, run)
    assert_inertia_page "Projects/WorkflowRuns/ShowPage"
  end

  test "create redirects on success" do
    create(:step, workflow: @workflow, position: 1, allow_non_interactive: true)
    mock_workflow_execution_start

    post company_project_workflow_runs_path(@project), params: {
      workflow_run: { workflow_id: @workflow.id, mode: "non_interactive" }
    }
    assert_response :redirect
  end

  test "cancel redirects" do
    run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user)
    WorkflowService.stubs(:cancel)

    post cancel_company_project_workflow_run_path(@project, run)
    assert_response :redirect
  end

  test "approve_step redirects" do
    step = create(:step, workflow: @workflow, position: 1)
    run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user)
    create(:step_run, workflow_run: run, step: step, state: "running")
    WorkflowService.stubs(:approve_step)

    post approve_step_company_project_workflow_run_path(@project, run)
    assert_response :redirect
  end

  test "retry_step redirects" do
    run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user)
    WorkflowService.stubs(:retry_step)

    post retry_step_company_project_workflow_run_path(@project, run)
    assert_response :redirect
  end

  test "skip_step redirects" do
    step = create(:step, workflow: @workflow, position: 1)
    run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user)
    create(:step_run, workflow_run: run, step: step, state: "running")
    WorkflowService.stubs(:skip_step)

    post skip_step_company_project_workflow_run_path(@project, run), params: { reason: "skip" }
    assert_response :redirect
  end

  test "viewer collaborator can read index but cannot create a run" do
    viewer = create(:user, :viewer, :onboarding_completed, company: @company,
                                    email: "client@ext.com", password: AuthHelper::TEST_PASSWORD)
    @project.add_collaborator(viewer)
    sign_in_as(viewer)

    get company_project_workflow_runs_path(@project)
    assert_inertia_page "Projects/WorkflowRuns/WorkflowRunsPage"

    post company_project_workflow_runs_path(@project), params: {
      workflow_run: { workflow_id: @workflow.id, mode: "non_interactive" }
    }
    assert_response :redirect
    assert_equal 0, WorkflowRun.where(project: @project).count
  end

  test "create normalizes camelCase step_overrides keys to snake_case" do
    create(:step, workflow: @workflow, position: 1, allow_non_interactive: true)
    mock_workflow_execution_start

    post company_project_workflow_runs_path(@project), params: {
      workflow_run: {
        workflow_id: @workflow.id,
        mode: "mixed",
        step_overrides: { "1" => { "autoRun" => true } }
      }
    }, as: :json

    assert_response :redirect
    assert_equal({ "1" => { "auto_run" => true } }, WorkflowRun.last.step_overrides)
  end

  test "create passes through already snake_case step_overrides keys unchanged" do
    create(:step, workflow: @workflow, position: 1, allow_non_interactive: true)
    mock_workflow_execution_start

    post company_project_workflow_runs_path(@project), params: {
      workflow_run: {
        workflow_id: @workflow.id,
        mode: "mixed",
        step_overrides: { "1" => { "auto_run" => true } }
      }
    }, as: :json

    assert_response :redirect
    assert_equal({ "1" => { "auto_run" => true } }, WorkflowRun.last.step_overrides)
  end

  test "create keeps only auto_run in a step override and drops unknown value fields (F16)" do
    create(:step, workflow: @workflow, position: 1, allow_non_interactive: true)
    mock_workflow_execution_start

    post company_project_workflow_runs_path(@project), params: {
      workflow_run: {
        workflow_id: @workflow.id,
        mode: "mixed",
        step_overrides: { "1" => { "auto_run" => true, "requested_model" => "sneaky", "evil" => { "x" => 1 } } }
      }
    }, as: :json

    assert_response :redirect
    assert_equal({ "1" => { "auto_run" => true } }, WorkflowRun.last.step_overrides)
  end
end
