# frozen_string_literal: true

# Per-user cost/token time series. Mirrors CompanySessionCostTokenUsageService but
# keys off a target user's sessions.
class UserSessionCostTokenUsageService
  PERIOD_DAYS = { "7d" => 7, "30d" => 30, "90d" => 90, "1y" => 365 }.freeze
  DATE_TRUNC_KEY = { "7d" => "day", "30d" => "day", "90d" => "week", "1y" => "month" }.freeze
  USAGE_SESSION_TYPES = %w[agent_session workflow_step].freeze

  TimeSeriesPoint = Struct.new(:date, :cost_cents, :total_tokens, keyword_init: true)

  Result = Struct.new(:time_series, keyword_init: true)

  def initialize(user:, company:, period:, project_id: nil)
    @user       = user
    @company    = company
    @period     = period.to_s
    @since      = PERIOD_DAYS.fetch(@period, 30).days.ago
    @project_id = project_id.presence
  end

  def call
    trunc = DATE_TRUNC_KEY.fetch(@period, "day")
    trunc_sql = Arel.sql("DATE_TRUNC('#{trunc}', terminal_sessions.created_at)")

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

  # Company isolation: usage sessions are always project-bound, so the inner
  # project join scopes the slice to the given company without a company_id
  # column on terminal_sessions.
  def base_sessions
    scope = user.terminal_sessions
                .joins(:project)
                .where(projects: { company_id: company.id })
                .where(created_at: since.., session_type: USAGE_SESSION_TYPES)
    project_id ? scope.where(project_id:) : scope
  end
end
