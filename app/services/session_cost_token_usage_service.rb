# frozen_string_literal: true

class SessionCostTokenUsageService
  include TaskFilterable

  PERIOD_DAYS = {
    "7d" => 7,
    "30d" => 30,
    "90d" => 90,
    "1y" => 365
  }.freeze

  DATE_TRUNC_KEY = {
    "7d"  => "day",
    "30d" => "day",
    "90d" => "week",
    "1y"  => "month"
  }.freeze

  TimeSeriesPoint = Struct.new(:date, :cost_cents, :total_tokens, keyword_init: true)
  Totals = Struct.new(:total_cost_cents, :total_tokens, :avg_cost_cents_per_session, keyword_init: true)
  Result = Struct.new(:time_series, :totals, keyword_init: true)

  def initialize(project:, user:, scope:, period:, tags: nil, task_type: nil, participant_id: nil)
    @project = project
    @user    = user
    @scope   = scope.to_s
    @period  = period.to_s
    @since   = PERIOD_DAYS.fetch(@period, 30).days.ago
    @tags      = Array(tags).presence
    @task_type = task_type.presence
    @participant_id = participant_id.presence
  end

  def call
    sessions = base_sessions

    trunc = DATE_TRUNC_KEY.fetch(period, "day")
    trunc_sql = Arel.sql("DATE_TRUNC('#{trunc}', terminal_sessions.created_at)")

    points = sessions
      .group(trunc_sql)
      .order(trunc_sql)
      .pluck(
        trunc_sql,
        Arel.sql("COALESCE(SUM(cost_cents), 0)"),
        Arel.sql("COALESCE(SUM(total_tokens), 0)")
      )
      .map do |(date, cost, tokens)|
        TimeSeriesPoint.new(
          date: date.to_date.iso8601,
          cost_cents: cost.to_i,
          total_tokens: tokens.to_i
        )
      end

    total_cost = points.sum(&:cost_cents)
    total_tokens = points.sum(&:total_tokens)
    total_count = sessions.count
    avg_cost = total_count.positive? ? (total_cost.to_f / total_count).round : 0

    totals = Totals.new(
      total_cost_cents: total_cost,
      total_tokens: total_tokens,
      avg_cost_cents_per_session: avg_cost
    )

    Result.new(time_series: points, totals: totals)
  end

  private

  attr_reader :project, :user, :scope, :since, :period, :tags, :task_type, :participant_id

  def base_sessions
    s = scope_sessions.where(created_at: since..)
    s = s.where(user_id: participant_id) if participant_id
    apply_task_filters(s)
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
