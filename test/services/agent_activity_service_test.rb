# frozen_string_literal: true

require "test_helper"

class AgentActivityServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  # Usage can keep arriving after a session's own totals were frozen, and a tool-setup
  # session is not usage; the breakdown has to count what the total counts.
  test "the per-agent breakdown adds up to the project's totals" do
    seed_session(agent_type: "claude_code", session_cost: 64, usage_cost: 71)
    seed_session(agent_type: "codex", session_cost: 0, usage_cost: 0)
    seed_session(agent_type: "claude_code", session_type: "tool_setup", session_cost: 5, usage_cost: 5)

    breakdown = AgentActivityService.new(**filters).call.sessions_by_agent
    totals = ProjectAnalyticsService.new(**filters).call

    assert_equal totals.total_sessions, breakdown.sum(&:sessions)
    assert_equal totals.total_cost_cents, breakdown.sum(&:cost_cents)
    assert_equal totals.total_tokens, breakdown.sum(&:tokens)
  end

  test "the company's per-agent breakdown adds up to its totals" do
    seed_session(agent_type: "claude_code", session_cost: 64, usage_cost: 71)
    seed_session(agent_type: "claude_code", session_type: "tool_setup", session_cost: 5, usage_cost: 5)
    filters = { company: @company, user: @user, scope: "company", period: "30d" }

    breakdown = CompanyAgentActivityService.new(**filters).call.sessions_by_agent
    totals = CompanyAnalyticsService.new(**filters).call

    assert_equal totals.total_sessions, breakdown.sum(&:sessions)
    assert_equal totals.total_cost_cents, breakdown.sum(&:cost_cents)
  end

  private

  def filters = { project: @project, user: @user, scope: "project", period: "30d" }

  def seed_session(agent_type:, session_cost:, usage_cost:, session_type: "agent_session")
    session = build(:terminal_session, user: @user, project: @project, session_type:, agent_type:,
                                       cost_cents: session_cost, total_tokens: 10)
    session.save!(validate: false)
    UsageStatistic.create!(terminal_session: session, cost_cents: usage_cost, input_tokens: 12,
                           output_tokens: 0, cache_write_tokens: 0, cache_read_tokens: 0, tokens: 12)
    session
  end
end
