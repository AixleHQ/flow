# frozen_string_literal: true

require "test_helper"

class CompanyWorkflowCostAnalyticsServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @admin)
    @workflow = create(:workflow, :with_project_scope, scope: @project)
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  def create_workflow_run_with_cost(project:, user:, cost_cents:, input_tokens:, output_tokens:, created_at: Time.current)
    workflow = project.workflows.first || create(:workflow, :with_project_scope, scope: project)
    run = create(:workflow_run, workflow: workflow, project: project, user: user, created_at: created_at)
    session = create(:terminal_session, user: user, project: project)
    step = create(:step, workflow: workflow)
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

  def call_service(scope:, period: "30d", user: @admin, company: @company)
    CompanyWorkflowCostAnalyticsService.new(
      company: company,
      user: user,
      scope: scope,
      period: period
    ).call
  end

  # ─── Scope: company ──────────────────────────────────────────────────────────

  test "company scope sums workflow-run costs across every project in the company" do
    other_project = create(:project, company: @company, owner: @admin)
    other_workflow = create(:workflow, :with_project_scope, scope: other_project)

    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 100, input_tokens: 500, output_tokens: 200)

    run2 = create(:workflow_run, workflow: other_workflow, project: other_project, user: @admin)
    session2 = create(:terminal_session, user: @admin, project: other_project)
    step2 = create(:step, workflow: other_workflow)
    create(:step_run, workflow_run: run2, step: step2, terminal_session: session2)
    UsageStatistic.create!(
      terminal_session: session2,
      cost_cents: 50, input_tokens: 100, output_tokens: 80,
      cache_write_tokens: 0, cache_read_tokens: 0, tokens: 180
    )

    result = call_service(scope: "company")

    assert { result.time_series.sum(&:cost_cents) == 150 }
  end

  test "excludes workflow runs belonging to a different company" do
    other_company = create(:company)
    other_admin = create(:user, :admin, company: other_company)
    other_project = create(:project, company: other_company, owner: other_admin)
    other_workflow = create(:workflow, :with_project_scope, scope: other_project)
    run = create(:workflow_run, workflow: other_workflow, project: other_project, user: other_admin)
    session = create(:terminal_session, user: other_admin, project: other_project)
    step = create(:step, workflow: other_workflow)
    create(:step_run, workflow_run: run, step: step, terminal_session: session)
    UsageStatistic.create!(
      terminal_session: session,
      cost_cents: 999, input_tokens: 100, output_tokens: 100,
      cache_write_tokens: 0, cache_read_tokens: 0, tokens: 200
    )

    result = call_service(scope: "company")

    assert { result.time_series.empty? }
  end

  test "company scope excludes runs outside the period window" do
    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 50, input_tokens: 100, output_tokens: 50, created_at: 60.days.ago)

    result = call_service(scope: "company", period: "30d")

    assert { result.time_series.empty? }
  end

  # ─── Scope: user ─────────────────────────────────────────────────────────────

  test "user scope returns only the current user's runs across the company" do
    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 200, input_tokens: 300, output_tokens: 100)
    create_workflow_run_with_cost(project: @project, user: @employee, cost_cents: 500, input_tokens: 600, output_tokens: 200)

    result = call_service(scope: "user", user: @admin)

    assert { result.time_series.sum(&:cost_cents) == 200 }
  end

  # ─── Time series bucketing ───────────────────────────────────────────────────

  test "returns daily points for 7d period" do
    3.times do |i|
      create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 10, input_tokens: 50, output_tokens: 20, created_at: i.days.ago)
    end

    result = call_service(scope: "company", period: "7d")

    assert { result.time_series.length == 3 }
    assert { result.time_series.all? { |p| p.date.match?(/\A\d{4}-\d{2}-\d{2}\z/) } }
  end

  test "returns weekly points for 90d period" do
    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 100, input_tokens: 500, output_tokens: 200, created_at: 10.days.ago)
    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 200, input_tokens: 800, output_tokens: 300, created_at: Time.current)

    result = call_service(scope: "company", period: "90d")

    assert { result.time_series.length == 2 }
  end

  test "returns monthly points for 1y period" do
    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 100, input_tokens: 500, output_tokens: 200, created_at: 1.month.ago)
    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 200, input_tokens: 800, output_tokens: 300, created_at: Time.current)

    result = call_service(scope: "company", period: "1y")

    assert { result.time_series.length == 2 }
  end

  # ─── Divergence from all-session cost series ─────────────────────────────────

  test "excludes standalone agent sessions that are not linked to workflow runs" do
    standalone = build(:terminal_session, project: @project, user: @admin,
                                         session_type: "agent_session", agent_type: "coding")
    standalone.save!(validate: false)
    UsageStatistic.create!(
      terminal_session: standalone,
      cost_cents: 300, input_tokens: 1000, output_tokens: 500,
      cache_write_tokens: 0, cache_read_tokens: 0, tokens: 1500
    )
    create_workflow_run_with_cost(project: @project, user: @admin, cost_cents: 100, input_tokens: 200, output_tokens: 100)

    workflow_result = call_service(scope: "company")
    session_result = CompanySessionCostTokenUsageService.new(
      company: @company, user: @admin, scope: "company", period: "30d"
    ).call

    assert { workflow_result.time_series.sum(&:cost_cents) == 100 }
    assert { session_result.time_series.sum(&:cost_cents) == 400 }
    assert { session_result.totals.total_cost_cents > workflow_result.time_series.sum(&:cost_cents) }
  end

  # ─── total_tokens fallback ───────────────────────────────────────────────────

  test "total_tokens falls back to the tokens column when the breakdown is zero" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @admin)
    session = create(:terminal_session, user: @admin, project: @project)
    step = create(:step, workflow: @workflow)
    create(:step_run, workflow_run: run, step: step, terminal_session: session)
    UsageStatistic.create!(
      terminal_session: session,
      cost_cents: 10, input_tokens: 0, output_tokens: 0,
      cache_write_tokens: 0, cache_read_tokens: 0, tokens: 500
    )

    result = call_service(scope: "company")

    assert { result.time_series.sum(&:total_tokens) == 500 }
  end
end
