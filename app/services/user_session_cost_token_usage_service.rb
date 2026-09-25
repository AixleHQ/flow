# frozen_string_literal: true

# Per-user cost/token time series. Mirrors CompanySessionCostTokenUsageService but
# keys off a target user's sessions.
class UserSessionCostTokenUsageService
  TimeSeriesPoint = Struct.new(:date, :cost_cents, :total_tokens, keyword_init: true)

  Result = Struct.new(:time_series, keyword_init: true)

  def initialize(user:, company:, period:, project_id: nil)
    @user       = user
    @company    = company
    @period     = period.to_s
    @since      = AnalyticsPeriod.since(@period)
    @project_id = project_id.presence
  end

  def call
    trunc_sql = AnalyticsPeriod.date_trunc(@period, TerminalSession.arel_table[:created_at])

    points = base_sessions
      .joins("LEFT JOIN usage_statistics ON usage_statistics.terminal_session_id = terminal_sessions.id")
      .group(trunc_sql)
      .order(trunc_sql)
      .pluck(
        trunc_sql,
        Arel.sql("COALESCE(SUM(usage_statistics.cost_cents), 0)"),
        Arel.sql("COALESCE(NULLIF(SUM(usage_statistics.input_tokens + usage_statistics.output_tokens + usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0), SUM(usage_statistics.tokens), 0)")
      )
      .map do |(date, cost, tokens)|
        TimeSeriesPoint.new(date: date.to_date.iso8601, cost_cents: cost.to_i, total_tokens: tokens.to_i)
      end

    Result.new(time_series: points)
  end

  private

  attr_reader :user, :company, :since, :project_id

  def base_sessions
    scope = user.terminal_sessions
                .where(company_id: company.id)
                .where(created_at: since.., session_type: AnalyticsPeriod::USAGE_SESSION_TYPES)
    project_id ? scope.where(project_id:) : scope
  end
end
