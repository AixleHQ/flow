# frozen_string_literal: true

require "test_helper"

class UserAgentActivityServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  def seed_session(agent_type:, cost_cents: 100, tokens: 1000, user: @user)
    session = build(:terminal_session, user:, project: @project,
                    session_type: "agent_session", agent_type:)
    session.save!(validate: false)
    UsageStatistic.create!(
      terminal_session: session,
      cost_cents:, input_tokens: tokens, output_tokens: 0,
      cache_write_tokens: 0, cache_read_tokens: 0, tokens:
    )
    session
  end

  test "groups by agent_type with cost and tokens" do
    seed_session(agent_type: "claude_code", cost_cents: 100, tokens: 1000)
    seed_session(agent_type: "claude_code", cost_cents: 200, tokens: 2000)
    seed_session(agent_type: "cursor_cli", cost_cents: 50, tokens: 500)

    result = UserAgentActivityService.new(user: @user, period: "30d", company: @company).call

    by_agent = result.sessions_by_agent.index_by(&:agent_type)
    assert { by_agent["claude_code"].sessions == 2 }
    assert { by_agent["claude_code"].cost_cents == 300 }
    assert { by_agent["claude_code"].tokens == 3000 }
    assert { by_agent["cursor_cli"].sessions == 1 }
    # Ordered by sessions desc
    assert { result.sessions_by_agent.first.agent_type == "claude_code" }
  end

  test "ignores sessions with a nil agent_type" do
    seed_session(agent_type: "claude_code")
    nil_agent = build(:terminal_session, user: @user, project: @project,
                      session_type: "workflow_step", agent_type: nil)
    nil_agent.save!(validate: false)

    result = UserAgentActivityService.new(user: @user, period: "30d", company: @company).call

    assert { result.sessions_by_agent.size == 1 }
    assert { result.sessions_by_agent.first.agent_type == "claude_code" }
  end
end
