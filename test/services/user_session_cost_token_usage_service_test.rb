# frozen_string_literal: true

require "test_helper"

class UserSessionCostTokenUsageServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  def seed_session(cost_cents:, tokens:, created_at: Time.current)
    session = build(:terminal_session, user: @user, project: @project,
                    session_type: "agent_session", agent_type: "claude_code", created_at:)
    session.save!(validate: false)
    UsageStatistic.create!(
      terminal_session: session,
      cost_cents:, input_tokens: tokens, output_tokens: 0,
      cache_write_tokens: 0, cache_read_tokens: 0, tokens:
    )
    session
  end

  test "7d period produces daily points with iso dates" do
    seed_session(cost_cents: 100, tokens: 1000)

    result = UserSessionCostTokenUsageService.new(user: @user, period: "7d").call

    assert { result.time_series.size == 1 }
    point = result.time_series.first
    assert { point.date.match?(/\A\d{4}-\d{2}-\d{2}\z/) }
    assert { point.cost_cents == 100 }
    assert { point.total_tokens == 1000 }
  end

  test "1y period buckets into months" do
    seed_session(cost_cents: 100, tokens: 1000, created_at: Time.current)
    seed_session(cost_cents: 200, tokens: 2000, created_at: 40.days.ago)

    result = UserSessionCostTokenUsageService.new(user: @user, period: "1y").call

    # Two different months → two monthly buckets.
    assert { result.time_series.size == 2 }
    assert { result.time_series.all? { |p| p.date.match?(/\A\d{4}-\d{2}-\d{2}\z/) } }
  end
end
