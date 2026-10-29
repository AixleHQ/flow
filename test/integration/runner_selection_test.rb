# frozen_string_literal: true

require "test_helper"

# Every endpoint that takes `runner_id`, and the props the runner selects and
# the runner page read (DESIGN.md §3.3, §11): a company without the flag has the
# field refused, and gets no runner options.
class RunnerSelectionTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user, name: "Payments")
    @workflow = create(:workflow, scope: @project, name: "Deploy")
    create(:step, workflow: @workflow, position: 1, allow_non_interactive: true)
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    @runner = create(:runner, company: @company, created_by: @user, name: "Prod VPC")
    sign_in_as(@user)
  end

  # == the run drawer ==

  test "the drawer's pick is refused without the flag" do
    post company_project_workflow_runs_path(@project), params: {
      workflow_run: { workflow_id: @workflow.id, mode: "non_interactive", runner_id: @runner.id }
    }, as: :json

    assert_equal 0, WorkflowRun.count
    assert_equal "External runners are not enabled for this company.", flash[:alert]
  end

  test "with the flag the drawer's pick is frozen on the run, which fails at launch" do
    enable_runners

    post company_project_workflow_runs_path(@project), params: {
      workflow_run: { workflow_id: @workflow.id, mode: "non_interactive", runner_id: @runner.id }
    }, as: :json

    run = WorkflowRun.sole
    assert_redirected_to company_project_workflow_run_path(@project, run)
    assert_equal [ @runner.id, "failed", "runner_execution_not_enabled" ], [ run.runner_id, run.state, run.failure_reason ]
  end

  test "a drawer that sends no pick runs on the workflow's runner, and a null pick is hosted" do
    enable_runners
    mock_workflow_execution_start
    @workflow.update!(runner: @runner)

    post company_project_workflow_runs_path(@project), params: {
      workflow_run: { workflow_id: @workflow.id, mode: "non_interactive" }
    }, as: :json
    post company_project_workflow_runs_path(@project), params: {
      workflow_run: { workflow_id: @workflow.id, mode: "non_interactive", runner_id: nil }
    }, as: :json

    assert_equal [ @runner.id, nil ], WorkflowRun.order(:id).pluck(:runner_id)
  end

  # == the task trigger API and the trigger tools ==

  test "the task trigger API refuses a pick without the flag" do
    task = bound_task

    post trigger_workflow_api_v1_project_task_path(@project, task), params: { runner_id: @runner.id }, as: :json

    assert_response :unprocessable_entity
    assert_equal [ "External runners are not enabled for this company." ], response.parsed_body["errors"]
    assert_equal 0, WorkflowRun.count
  end

  test "the task trigger API carries the pick onto the run" do
    enable_runners
    task = bound_task

    post trigger_workflow_api_v1_project_task_path(@project, task), params: { runner_id: @runner.id }, as: :json

    assert_response :success
    assert_equal @runner.id, task.workflow_runs.sole.runner_id
  end

  test "trigger_workflow refuses a pick without the flag and takes it with the flag" do
    tool = ->(args) { PersonalTools::TriggerWorkflow.new(params: args, user: @user).execute }
    args = { project_id: @project.id, workflow_id: @workflow.id, mode: "non_interactive", runner_id: @runner.id }

    refused = tool.call(args)
    assert_equal 1, refused[:exit_code]
    assert_match(/External runners are not enabled for this company/, refused[:stderr])

    taken = with_feature(:external_runners, true, company: @company) { tool.call(args) }
    assert_equal @runner.id, WorkflowRun.find(JSON.parse(taken[:stdout])["run_id"]).runner_id
  end

  # == the session API ==

  test "the session API refuses a pick without the flag" do
    post api_v1_terminal_sessions_path, params: { terminal_session: session_params(runner_id: @runner.id) }, as: :json

    assert_response :unprocessable_entity
    assert_equal [ "External runners are not enabled for this company." ], response.parsed_body["errors"]
  end

  test "with the flag the session API saves the session on its runner, failed with the message" do
    enable_runners

    post api_v1_terminal_sessions_path, params: { terminal_session: session_params(runner_id: @runner.id) }, as: :json

    assert_response :created
    session = TerminalSession.sole
    assert_equal [ @runner.id, "failed" ], [ session.runner_id, session.state ]
    assert_equal session.error_message, response.parsed_body["errorMessage"]
    assert_equal "Prod VPC", response.parsed_body.dig("runner", "name")
  end

  # == the builder ==

  test "the builder's save refuses a runner without the flag" do
    save_workflow(runner_id: @runner.id)

    assert_response :unprocessable_entity
    assert_equal [ "External runners are not enabled for this company." ], response.parsed_body["errors"]
    assert_nil @workflow.reload.runner_id
  end

  test "with the flag the builder saves the runner as a new version, and keeps one that went away since" do
    enable_runners

    save_workflow(runner_id: @runner.id)
    assert_response :success
    assert_equal @runner.id, @workflow.reload.runner_id
    assert_equal @runner.id, response.parsed_body.dig("workflow", "runnerId")

    @runner.soft_delete!
    save_workflow(runner_id: @runner.id, description: "still editable")
    assert_response :success
    assert_equal "still editable", @workflow.reload.description
  end

  test "the builder offers the visible runners, and the workflow's own once deleted, only with the flag" do
    deleted = create(:runner, company: @company, created_by: @user, name: "Old box")
    @workflow.update!(runner: deleted)
    deleted.soft_delete!

    get builder_company_project_workflow_path(@project, @workflow), headers: deferred("runners")
    assert_equal [], response.parsed_body.dig("props", "runners")

    enable_runners
    get builder_company_project_workflow_path(@project, @workflow), headers: deferred("runners")
    runners = response.parsed_body.dig("props", "runners")
    assert_equal [ [ "Prod VPC", false ], [ "Old box", true ] ], runners.map { |r| [ r["name"], r["deleted"] ] }
    assert_equal @company.name, runners.first["operatedBy"]
  end

  # == the runner page ==

  test "the runner page lists the workflows using it" do
    enable_runners
    @workflow.update!(runner: @runner)
    create(:workflow, scope: @project, name: "Archived", runner: @runner).update!(deleted_at: Time.current)

    get company_settings_runner_path(@runner), headers: { "X-Inertia" => "true" }

    assert_equal [ { "id" => @workflow.id, "name" => "Deploy", "projectId" => @project.id, "projectName" => "Payments" } ],
                 response.parsed_body.dig("props", "workflowsUsing")
  end

  private

  def enable_runners
    FeatureFlag.find_or_create_by!(key: "external_runners").overrides.create!(company: @company, enabled: true, reason: "test")
  end

  def bound_task
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    ColumnWorkflowBinding.create!(board_column: column, workflow: @workflow, trigger_mode: :manual, cooldown_seconds: 0)
    create(:board_task, board: board, board_column: column)
  end

  def session_params(**extra)
    { project_id: @project.id, session_type: "agent_session", agent_type: "claude_code", mode: "non_interactive",
      initial_prompt: "go", **extra }
  end

  def save_workflow(**attrs)
    put api_v1_project_workflow_aggregate_path(@project, @workflow),
        params: { base_version: @workflow.reload.current_version_number,
                  aggregate: { name: "Deploy", **attrs,
                               steps: @workflow.steps.not_deleted.map { |s| { id: s.id, name: s.name } } } },
        as: :json
  end

  def deferred(*props)
    { "X-Inertia" => "true", "X-Inertia-Partial-Component" => "Projects/Workflows/BuilderPage",
      "X-Inertia-Partial-Data" => props.join(",") }
  end
end
