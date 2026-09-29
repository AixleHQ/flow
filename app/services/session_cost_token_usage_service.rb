# frozen_string_literal: true

class SessionCostTokenUsageService
  include TaskFilterable

  TimeSeriesPoint = Struct.new(:date, :cost_cents, :total_tokens, keyword_init: true)
  Totals = Struct.new(:total_cost_cents, :total_tokens, :avg_cost_cents_per_session, keyword_init: true)
  Result = Struct.new(:time_series, :totals, keyword_init: true)

  def initialize(project:, user:, scope:, period:, tags: nil, task_type: nil, participant_id: nil)
    @project = project
    @user    = user
    @scope   = scope.to_s
    @period  = period.to_s
    @since   = AnalyticsPeriod.since(@period)
    @tags      = Array(tags).presence
    @task_type = task_type.presence
    @participant_id = participant_id.presence
  end

  def call
    sessions = base_sessions

    trunc_sql = AnalyticsPeriod.date_trunc(period, TerminalSession.arel_table[:created_at])

    # Spend comes from usage_statistics, like every other analytics number: the
    # session's own cost columns are only copied over when it ends, so a running
    # session showed nothing here while the summary above already counted it.
    points = sessions
      .joins("LEFT JOIN usage_statistics ON usage_statistics.terminal_session_id = terminal_sessions.id")
      .group(trunc_sql)
      .order(trunc_sql)
      .pluck(
        trunc_sql,
        Arel.sql("COALESCE(SUM(usage_statistics.cost_cents), 0)"),
        Arel.sql("COALESCE(NULLIF(SUM(usage_statistics.input_tokens + usage_statistics.output_tokens + usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0), SUM(usage_statistics.tokens), 0)")
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
    s = scope_sessions.where(created_at: since.., session_type: AnalyticsPeriod::USAGE_SESSION_TYPES)
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
