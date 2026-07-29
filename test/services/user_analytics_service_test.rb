# frozen_string_literal: true

require "test_helper"

class UserAnalyticsServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @other = create(:user, :employee, company: @company)
    @project_a = create(:project, company: @company, owner: @user)
    @project_b = create(:project, company: @company, owner: @user)
  end

  # Seed a billable session for a user with an optional project + usage stats.
  def seed_session(user:, project:, cost_cents:, tokens:, agent_type: "claude_code",
                   session_type: "agent_session", created_at: Time.current)
    session = build(:terminal_session, user:, project:, session_type:, agent_type:, created_at:)
    session.save!(validate: false)
    UsageStatistic.create!(
      terminal_session: session,
      cost_cents:, input_tokens: tokens, output_tokens: 0,
      cache_write_tokens: 0, cache_read_tokens: 0, tokens:
    )
    session
  end

  def call(user: @user, period: "30d", project_id: nil)
    UserAnalyticsService.new(user:, company: @company, period:, project_id:).call
  end

  test "aggregates only the given user's sessions across multiple projects" do
    seed_session(user: @user, project: @project_a, cost_cents: 100, tokens: 1000)
    seed_session(user: @user, project: @project_b, cost_cents: 200, tokens: 2000)
    seed_session(user: @other, project: @project_a, cost_cents: 999, tokens: 9999)

    result = call

    assert { result.total_sessions == 2 }
    assert { result.total_cost_cents == 300 }
    assert { result.total_tokens == 3000 }
  end

  test "project_breakdowns has one row per project ordered by cost desc summing to totals" do
    seed_session(user: @user, project: @project_a, cost_cents: 100, tokens: 1000)
    seed_session(user: @user, project: @project_b, cost_cents: 500, tokens: 2000)

    result = call

    assert { result.project_breakdowns.size == 2 }
    assert { result.project_breakdowns.first.cost_cents == 500 }
    assert { result.project_breakdowns.sum(&:sessions) == result.total_sessions }
    assert { result.project_breakdowns.sum(&:cost_cents) == result.total_cost_cents }
    assert { result.project_breakdowns.sum(&:tokens) == result.total_tokens }
  end

  test "project-less (legacy) sessions are excluded from company-scoped analytics" do
    seed_session(user: @user, project: @project_a, cost_cents: 100, tokens: 1000)
    seed_session(user: @user, project: nil, cost_cents: 250, tokens: 500)

    result = call

    # NULL-project sessions cannot be attributed to a company, so the inner
    # project join drops them from totals AND breakdowns (reconciliation holds).
    assert { result.total_sessions == 1 }
    assert { result.total_cost_cents == 100 }
    assert { result.total_tokens == 1000 }
    assert { result.project_breakdowns.size == 1 }
    assert { result.project_breakdowns.none? { |p| p.project_id.nil? } }
    assert { result.project_breakdowns.sum(&:cost_cents) == result.total_cost_cents }
  end

  test "period window excludes rows older than the period" do
    seed_session(user: @user, project: @project_a, cost_cents: 100, tokens: 1000, created_at: 60.days.ago)

    result = call(period: "30d")

    assert { result.total_sessions == 0 }
    assert { result.project_breakdowns.empty? }
  end

  test "total_tokens uses legacy tokens fallback when breakdown columns are zero" do
    session = build(:terminal_session, user: @user, project: @project_a, session_type: "agent_session", agent_type: "claude_code")
    session.save!(validate: false)
    UsageStatistic.create!(
      terminal_session: session,
      cost_cents: 0, input_tokens: 0, output_tokens: 0,
      cache_write_tokens: 0, cache_read_tokens: 0, tokens: 500
    )

    result = call

    assert { result.total_tokens == 500 }
  end

  test "auth_setup and tool_setup sessions are excluded" do
    seed_session(user: @user, project: @project_a, cost_cents: 100, tokens: 1000)
    seed_session(user: @user, project: nil, cost_cents: 50, tokens: 50, session_type: "auth_setup")
    tool = build(:terminal_session, user: @user, project: @project_a, session_type: "tool_setup", agent_type: "claude_code")
    tool.save!(validate: false)

    result = call

    assert { result.total_sessions == 1 }
    assert { result.total_cost_cents == 100 }
  end

  test "project_id argument restricts all metrics to that project" do
    seed_session(user: @user, project: @project_a, cost_cents: 100, tokens: 1000)
    seed_session(user: @user, project: @project_b, cost_cents: 999, tokens: 9999)

    result = call(project_id: @project_a.id)

    assert { result.total_sessions == 1 }
    assert { result.total_cost_cents == 100 }
    assert { result.project_breakdowns.size == 1 }
  end
end
