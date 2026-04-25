# frozen_string_literal: true

class CompanyAgentActivityService
  PERIOD_DAYS = {
    "7d" => 7,
    "30d" => 30,
    "90d" => 90,
    "1y" => 365
  }.freeze

  AgentBreakdown = Struct.new(:agent_type, :sessions, :cost_cents, :tokens, keyword_init: true)
  ActivityPoint = Struct.new(:date, :agent_type, :sessions, keyword_init: true)

  Result = Struct.new(:agent_types, :sessions_by_agent, :activity_over_time, keyword_init: true)

  def initialize(company:, user:, scope:, period:)
    @company = company
    @user = user
    @scope = scope.to_s
    @since = PERIOD_DAYS.fetch(period.to_s, 30).days.ago
  end

  def call
    sessions = base_sessions

    sessions_by_agent = sessions
      .where.not(agent_type: nil)
      .joins("LEFT JOIN usage_statistics ON usage_statistics.terminal_session_id = terminal_sessions.id")
      .group(:agent_type)
      .pluck(
        :agent_type,
        Arel.sql("COUNT(terminal_sessions.id)"),
        Arel.sql("COALESCE(SUM(usage_statistics.cost_cents), 0)"),
        Arel.sql("COALESCE(NULLIF(SUM(usage_statistics.input_tokens + usage_statistics.output_tokens + usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0), SUM(usage_statistics.tokens), 0)")
      )
      .map do |(agent_type, count, cost, tokens)|
        AgentBreakdown.new(
          agent_type:,
          sessions: count,
          cost_cents: cost,
          tokens: tokens
        )
      end
      .sort_by { |a| -a.sessions }

    agent_types = sessions_by_agent.map(&:agent_type)

    activity_over_time = sessions
      .where.not(agent_type: nil)
      .group(Arel.sql("date_trunc('day', terminal_sessions.created_at)"), :agent_type)
      .order(Arel.sql("1 ASC"))
      .pluck(
        Arel.sql("date_trunc('day', terminal_sessions.created_at)"),
        :agent_type,
        Arel.sql("COUNT(*)")
      )
      .map do |(date, agent_type, count)|
        ActivityPoint.new(
          date: date.to_date.iso8601,
          agent_type:,
          sessions: count
        )
      end

    Result.new(
      agent_types:,
      sessions_by_agent:,
      activity_over_time:
    )
  end

  private

  attr_reader :company, :user, :scope, :since

  def base_sessions
    scope_sessions.where(created_at: since..)
  end

  def scope_sessions
    base = TerminalSession.joins(:project).where(projects: { company_id: company.id })
    scope == "user" ? base.where(user:) : base
  end
end
