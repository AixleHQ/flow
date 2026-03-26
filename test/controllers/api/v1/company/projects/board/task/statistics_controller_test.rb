# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Board::Task::StatisticsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @owner = create(:user, :employee, company: @company)
    @other_user = create(:user, :employee, company: create(:company, email_domain: "other.com"))

    @project = create(:project, company: @company, owner: @owner)
    @board = Board.create!(name: "Dev Board", project: @project)
    @col = BoardColumn.create!(name: "Backlog", board: @board, position: 1)
    @task = BoardTask.create!(title: "Test Task", board: @board, board_column: @col)
    @workflow = create(:workflow, :with_company_scope, scope: @company)
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  def create_run_with_usage(cost_cents:, input_tokens:, output_tokens:, started_at: 1.hour.ago, completed_at: Time.current)
    run = WorkflowRun.create!(
      workflow: @workflow,
      project: @project,
      user: @owner,
      board_task: @task,
      state: "completed",
      started_at: started_at,
      completed_at: completed_at
    )
    session = create(:terminal_session, user: @owner, project: @project)
    step = create(:step, workflow: @workflow)
    create(:step_run, workflow_run: run, step: step, terminal_session: session)
    UsageStatistic.create!(
      terminal_session: session,
      cost_cents: cost_cents,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cache_write_tokens: 0,
      cache_read_tokens: 0,
      tokens: input_tokens + output_tokens
    )
    run
  end

  # ─── Shape tests ─────────────────────────────────────────────────────────────

  test "#show returns statistics with expected keys" do
    sign_in @owner
    get :show, params: { project_id: @project.id, task_id: @task.id }
    assert_response :success
    json = response.parsed_body
    assert json.key?("costTotals")
    assert json.key?("tokenTotals")
    assert json.key?("timeTotals")
    assert json.key?("waitStats")
    assert json.key?("workflowBreakdowns")
  end

  test "#show returns empty arrays for task with no data" do
    sign_in @owner
    get :show, params: { project_id: @project.id, task_id: @task.id }
    assert_response :success
    json = response.parsed_body
    assert_equal [], json["waitStats"]
    assert_equal [], json["workflowBreakdowns"]
  end

  test "#show is forbidden for non-member" do
    sign_in @other_user
    get :show, params: { project_id: @project.id, task_id: @task.id }
    assert_includes [ 403, 404 ], response.status
  end

  test "#show returns 404 for unknown task" do
    sign_in @owner
    get :show, params: { project_id: @project.id, task_id: 0 }
    assert_response :not_found
  end

  # ─── Data correctness: cost and token totals ─────────────────────────────────

  test "#show aggregates cost and token totals correctly across multiple runs" do
    create_run_with_usage(cost_cents: 100, input_tokens: 500, output_tokens: 200)
    create_run_with_usage(cost_cents: 250, input_tokens: 800, output_tokens: 300)

    sign_in @owner
    get :show, params: { project_id: @project.id, task_id: @task.id }
    assert_response :success

    json = response.parsed_body

    assert_equal 350, json.dig("costTotals", "totalCostCents")
    assert_equal 1800, json.dig("tokenTotals", "totalTokens")
  end

  # ─── Data correctness: time totals ───────────────────────────────────────────

  test "#show calculates time totals from completed_at minus started_at" do
    t0 = 2.hours.ago
    t1 = 1.hour.ago
    t2 = 30.minutes.ago
    t3 = Time.current

    create_run_with_usage(cost_cents: 10, input_tokens: 10, output_tokens: 10, started_at: t0, completed_at: t1)
    create_run_with_usage(cost_cents: 10, input_tokens: 10, output_tokens: 10, started_at: t2, completed_at: t3)

    sign_in @owner
    get :show, params: { project_id: @project.id, task_id: @task.id }
    assert_response :success

    json = response.parsed_body
    expected_total = (t1 - t0).round + (t3 - t2).round

    assert_in_delta expected_total, json.dig("timeTotals", "totalDurationSeconds"), 2
  end

  # ─── Data correctness: workflow breakdowns ───────────────────────────────────

  test "#show groups workflow breakdowns by workflow" do
    workflow2 = create(:workflow, :with_company_scope, scope: @company)

    run1_start = 2.hours.ago
    run1 = WorkflowRun.create!(
      workflow: @workflow,
      project: @project,
      user: @owner,
      board_task: @task,
      state: "completed",
      started_at: run1_start,
      completed_at: run1_start + 30.minutes
    )
    session1 = create(:terminal_session, user: @owner, project: @project)
    step1 = create(:step, workflow: @workflow)
    create(:step_run, workflow_run: run1, step: step1, terminal_session: session1)
    UsageStatistic.create!(
      terminal_session: session1,
      cost_cents: 300, input_tokens: 400, output_tokens: 100,
      cache_write_tokens: 0, cache_read_tokens: 0, tokens: 500
    )

    run2_start = 1.hour.ago
    run2 = WorkflowRun.create!(
      workflow: workflow2,
      project: @project,
      user: @owner,
      board_task: @task,
      state: "completed",
      started_at: run2_start,
      completed_at: run2_start + 15.minutes
    )
    session2 = create(:terminal_session, user: @owner, project: @project)
    step2 = create(:step, workflow: workflow2)
    create(:step_run, workflow_run: run2, step: step2, terminal_session: session2)
    UsageStatistic.create!(
      terminal_session: session2,
      cost_cents: 150, input_tokens: 200, output_tokens: 50,
      cache_write_tokens: 0, cache_read_tokens: 0, tokens: 250
    )

    sign_in @owner
    get :show, params: { project_id: @project.id, task_id: @task.id }
    assert_response :success

    json = response.parsed_body
    breakdowns = json["workflowBreakdowns"]

    assert_equal 2, breakdowns.size

    wf1_entry = breakdowns.find { |b| b["workflowId"] == @workflow.id }
    wf2_entry = breakdowns.find { |b| b["workflowId"] == workflow2.id }

    assert_not_nil wf1_entry
    assert_not_nil wf2_entry
    assert_equal 300, wf1_entry["costCents"]
    assert_equal 150, wf2_entry["costCents"]
  end

  test "#show returns empty workflowBreakdowns when task has no runs" do
    sign_in @owner
    get :show, params: { project_id: @project.id, task_id: @task.id }
    assert_response :success

    json = response.parsed_body
    assert_equal [], json["workflowBreakdowns"]
  end

  # ─── Data correctness: wait stats ────────────────────────────────────────────

  test "#show returns wait stats with correct status and duration for resolved waits" do
    resolved_at = 30.minutes.ago
    wait = TaskWait.create!(
      board_task: @task,
      creator: @owner,
      wait_type: "github_checks_completed",
      status: "resolved",
      resolved_at: resolved_at,
      created_at: 1.hour.ago
    )

    sign_in @owner
    get :show, params: { project_id: @project.id, task_id: @task.id }
    assert_response :success

    json = response.parsed_body
    wait_stats = json["waitStats"]

    assert_equal 1, wait_stats.size
    stat = wait_stats.first
    assert_equal wait.id, stat["id"]
    assert_equal "github_checks_completed", stat["waitType"]
    assert_equal "resolved", stat["status"]
    assert_not_nil stat["resolvedAt"]
    assert_in_delta 1800, stat["durationSeconds"], 5
  end

  test "#show returns nil durationSeconds for pending waits" do
    TaskWait.create!(
      board_task: @task,
      creator: @owner,
      wait_type: "github_checks_completed",
      status: "pending",
      created_at: 1.hour.ago
    )

    sign_in @owner
    get :show, params: { project_id: @project.id, task_id: @task.id }
    assert_response :success

    json = response.parsed_body
    stat = json["waitStats"].first
    assert_equal "pending", stat["status"]
    assert_nil stat["durationSeconds"]
    assert_nil stat["resolvedAt"]
  end
end
