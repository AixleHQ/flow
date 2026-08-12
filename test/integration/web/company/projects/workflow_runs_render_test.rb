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
end
