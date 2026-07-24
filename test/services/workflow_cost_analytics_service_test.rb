# frozen_string_literal: true

require "test_helper"

class WorkflowCostAnalyticsServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @admin)
    @workflow = create(:workflow, :with_project_scope, scope: @project)
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  def create_workflow_run_with_cost(project:, user:, cost_cents:, input_tokens:, output_tokens:, created_at: Time.current)
    run = create(:workflow_run, workflow: @workflow, project: project, user: user, created_at: created_at)
    session = create(:terminal_session, user: user, project: project)
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

  def call_service(scope:, period: "30d", user: @admin, project: @project)
    WorkflowCostAnalyticsService.new(
      project: project,
      user: user,
      scope: scope,
      period: period
    ).call
  end

  # ─── Scope: project ──────────────────────────────────────────────────────────

  test "project scope returns workflow runs for the given project" do
    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 100, input_tokens: 500, output_tokens: 200)

    other_project = create(:project, company: @company, owner: @admin)
    create_workflow_run_with_cost(project: other_project, user: @admin, cost_cents: 999, input_tokens: 1000, output_tokens: 500)

    result = call_service(scope: "project")

    assert { result.workflows.size == 1 }
    assert { result.workflows.first.total_cost_cents == 100 }
  end

  test "project scope excludes runs outside the period window" do
    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 50, input_tokens: 100, output_tokens: 50, created_at: 60.days.ago)

    result = call_service(scope: "project", period: "30d")

    assert { result.workflows.empty? }
    assert { result.totals[:total_cost_cents] == 0 }
  end

  # ─── Scope: user ─────────────────────────────────────────────────────────────

  test "user scope returns only the current user's runs in the project" do
    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 200, input_tokens: 300, output_tokens: 100)
    create_workflow_run_with_cost(project: @project, user: @employee, cost_cents: 500, input_tokens: 600, output_tokens: 200)

    result = call_service(scope: "user", user: @admin)

    assert { result.workflows.size == 1 }
    assert { result.workflows.first.total_cost_cents == 200 }
  end

  # ─── Aggregate totals ────────────────────────────────────────────────────────

  test "aggregate_totals sums cost and tokens across all workflow rows" do
    workflow2 = create(:workflow, :with_project_scope, scope: @project)
    run2 = create(:workflow_run, workflow: workflow2, project: @project, user: @admin)
    session2 = create(:terminal_session, user: @admin, project: @project)
    step2 = create(:step, workflow: workflow2)
    create(:step_run, workflow_run: run2, step: step2, terminal_session: session2)
    UsageStatistic.create!(
      terminal_session: session2,
      cost_cents: 50,
      input_tokens: 100,
      output_tokens: 80,
      cache_write_tokens: 0,
      cache_read_tokens: 0,
      tokens: 180
    )

    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 150, input_tokens: 300, output_tokens: 200)

    result = call_service(scope: "project")

    assert { result.totals[:total_cost_cents] == 200 }
    assert { result.totals[:workflow_count] == 2 }
    assert { result.totals[:total_tokens] == result.workflows.sum(&:total_tokens) }
  end

  # ─── Time series bucketing ───────────────────────────────────────────────────

  test "build_time_series returns daily points for 7d period" do
    3.times do |i|
      create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 10, input_tokens: 50, output_tokens: 20, created_at: i.days.ago)
    end

    result = call_service(scope: "project", period: "7d")

    assert { result.time_series.length == 3 }
    assert { result.time_series.all? { |p| p.date.match?(/\A\d{4}-\d{2}-\d{2}\z/) } }
  end

  test "build_time_series returns monthly points for 1y period" do
    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 100, input_tokens: 500, output_tokens: 200, created_at: 1.month.ago)
    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 200, input_tokens: 800, output_tokens: 300, created_at: Time.current)

    result = call_service(scope: "project", period: "1y")

    assert { result.time_series.length == 2 }
  end

  # ─── total_tokens fallback ───────────────────────────────────────────────────

  test "total_tokens falls back to tokens column when breakdown is zero" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @admin)
    session = create(:terminal_session, user: @admin, project: @project)
    step = create(:step, workflow: @workflow)
    create(:step_run, workflow_run: run, step: step, terminal_session: session)
    UsageStatistic.create!(
      terminal_session: session,
      cost_cents: 10,
      input_tokens: 0,
      output_tokens: 0,
      cache_write_tokens: 0,
      cache_read_tokens: 0,
      tokens: 500
    )

    result = call_service(scope: "project")

    assert { result.totals[:total_tokens] == 500 }
  end
end
