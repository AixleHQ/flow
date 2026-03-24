# frozen_string_literal: true

require "test_helper"

class SessionCostTokenUsageServiceTest < ActiveSupport::TestCase
  setup do
    @company  = create(:company)
    @admin    = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @project  = create(:project, company: @company, owner: @admin)
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  def create_session_with_usage(project:, user:, cost_cents:, total_tokens:, created_at: Time.current)
    create(:terminal_session,
      project: project,
      user: user,
      session_type: "agent_session",
      cost_cents: cost_cents,
      total_tokens: total_tokens,
      created_at: created_at)
  end

  def call_service(scope:, period: "30d", user: @admin, project: @project)
    SessionCostTokenUsageService.new(
      project: project,
      user: user,
      scope: scope,
      period: period
    ).call
  end

  # ─── Scope: project ──────────────────────────────────────────────────────────

  test "project scope returns sessions for the given project only" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 100, total_tokens: 500)

    other_project = create(:project, company: @company, owner: @admin)
    create_session_with_usage(project: other_project, user: @admin, cost_cents: 999, total_tokens: 9999)

    result = call_service(scope: "project")

    assert { result.totals.total_cost_cents == 100 }
    assert { result.totals.total_tokens == 500 }
  end

  test "project scope excludes sessions outside the period window" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 50, total_tokens: 200,
      created_at: 60.days.ago)

    result = call_service(scope: "project", period: "30d")

    assert { result.totals.total_cost_cents == 0 }
    assert { result.totals.total_tokens == 0 }
  end

  # ─── Scope: user ─────────────────────────────────────────────────────────────

  test "user scope returns only the current user's sessions in the project" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 200, total_tokens: 300)
    create_session_with_usage(project: @project, user: @employee, cost_cents: 500, total_tokens: 600)

    result = call_service(scope: "user", user: @admin)

    assert { result.totals.total_cost_cents == 200 }
    assert { result.totals.total_tokens == 300 }
  end

  # ─── Aggregate totals ────────────────────────────────────────────────────────

  test "totals sums cost and tokens across all sessions" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 100, total_tokens: 200)
    create_session_with_usage(project: @project, user: @admin, cost_cents: 50, total_tokens: 100)

    result = call_service(scope: "project")

    assert { result.totals.total_cost_cents == 150 }
    assert { result.totals.total_tokens == 300 }
  end

  test "avg_cost_cents_per_session is calculated correctly" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 100, total_tokens: 200)
    create_session_with_usage(project: @project, user: @admin, cost_cents: 200, total_tokens: 400)

    result = call_service(scope: "project")

    assert { result.totals.avg_cost_cents_per_session == 150 }
  end

  test "avg_cost_cents_per_session is zero when no sessions exist" do
    result = call_service(scope: "project")

    assert { result.totals.avg_cost_cents_per_session == 0 }
  end

  # ─── Time series bucketing ───────────────────────────────────────────────────

  test "returns daily time series points for 7d period" do
    3.times do |i|
      create_session_with_usage(project: @project, user: @admin, cost_cents: 10, total_tokens: 50,
        created_at: i.days.ago)
    end

    result = call_service(scope: "project", period: "7d")

    assert { result.time_series.length == 3 }
    assert { result.time_series.all? { |p| p.date.match?(/\A\d{4}-\d{2}-\d{2}\z/) } }
  end

  test "returns monthly time series points for 1y period" do
    create_session_with_usage(project: @project, user: @admin, cost_cents: 100, total_tokens: 500,
      created_at: 1.month.ago)
    create_session_with_usage(project: @project, user: @admin, cost_cents: 200, total_tokens: 800,
      created_at: Time.current)

    result = call_service(scope: "project", period: "1y")

    assert { result.time_series.length == 2 }
  end

  test "aggregates multiple sessions on the same day into one time series point" do
    2.times do
      create_session_with_usage(project: @project, user: @admin, cost_cents: 50, total_tokens: 100,
        created_at: Time.current)
    end

    result = call_service(scope: "project", period: "7d")

    assert { result.time_series.length == 1 }
    assert { result.time_series.first.cost_cents == 100 }
    assert { result.time_series.first.total_tokens == 200 }
  end

  test "returns empty time series and zero totals when no sessions exist" do
    result = call_service(scope: "project")

    assert { result.time_series.empty? }
    assert { result.totals.total_cost_cents == 0 }
    assert { result.totals.total_tokens == 0 }
  end
end
