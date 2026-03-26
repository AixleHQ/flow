# frozen_string_literal: true

class AgentActivityService
  include TaskFilterable

  PERIOD_DAYS = {
    "7d" => 7,
    "30d" => 30,
    "90d" => 90,
    "1y" => 365
  }.freeze

  AgentBreakdown = Struct.new(:agent_type, :sessions, :cost_cents, :tokens, keyword_init: true)
  ActivityPoint = Struct.new(:date, :agent_type, :sessions, keyword_init: true)

  Result = Struct.new(:agent_types, :sessions_by_agent, :activity_over_time, keyword_init: true)

  def initialize(project:, user:, scope:, period:, tags: nil, task_type: nil)
    @project = project
    @user = user
    @scope = scope.to_s
    @since = PERIOD_DAYS.fetch(period.to_s, 30).days.ago
    @period = period.to_s
    @tags = Array(tags).presence
    @task_type = task_type.presence
  end

  def call
    sessions = base_sessions

    sessions_by_agent = sessions
      .where.not(agent_type: nil)
      .group(:agent_type)
      .pluck(
        :agent_type,
        Arel.sql("COUNT(*)"),
        Arel.sql("COALESCE(SUM(cost_cents), 0)"),
        Arel.sql("COALESCE(SUM(total_tokens), 0)")
      )
      .map do |(agent_type, count, cost, tokens)|
        AgentBreakdown.new(
          agent_type: agent_type,
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
          agent_type: agent_type,
          sessions: count
        )
      end

    Result.new(
      agent_types: agent_types,
      sessions_by_agent: sessions_by_agent,
      activity_over_time: activity_over_time
    )
  end

  private

  attr_reader :project, :user, :scope, :since, :tags, :task_type

  def base_sessions
    scope_sessions.where(created_at: since..).then { |s| apply_task_filters(s) }
  end

  def scope_sessions
    case scope
    when "user"
      project.terminal_sessions.where(user: user)
    else
      project.terminal_sessions
    end
  end
end
