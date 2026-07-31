# frozen_string_literal: true

# Company-wide counterpart to WorkflowCostAnalyticsService (which is project-scoped).
# Only computes the daily cost/token time series across all of the company's workflow
# runs — that's the one thing the Company Analytics page's Cost & Token Usage "Workflows
# only" toggle needs; it has no per-workflow breakdown table to feed like the project page.
# Bucketing and period filtering use workflow_runs.created_at (not terminal_sessions.created_at
# like CompanySessionCostTokenUsageService) — intentional: workflow spend is attributed to run start.
class CompanyWorkflowCostAnalyticsService
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
  Result = Struct.new(:time_series, keyword_init: true)

  def initialize(company:, user:, scope:, period:)
    @company = company
    @user    = user
    @scope   = scope.to_s
    @period  = period.to_s
    @since   = PERIOD_DAYS.fetch(@period, 30).days.ago
  end

  def call
    trunc = DATE_TRUNC_KEY.fetch(period, "day")
    trunc_sql = Arel.sql("DATE_TRUNC('#{trunc}', workflow_runs.created_at)")

    points = base_runs
      .joins("LEFT JOIN step_runs ON step_runs.workflow_run_id = workflow_runs.id")
      .joins("LEFT JOIN usage_statistics ON usage_statistics.terminal_session_id = step_runs.terminal_session_id")
      .group(trunc_sql)
      .order(trunc_sql)
      .pluck(
        trunc_sql,
        Arel.sql("COALESCE(SUM(usage_statistics.cost_cents), 0)"),
        Arel.sql("COALESCE(NULLIF(SUM(usage_statistics.input_tokens + usage_statistics.output_tokens + " \
                 "usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0), " \
                 "SUM(usage_statistics.tokens), 0)")
      )
      .map do |(date, cost, tokens)|
        TimeSeriesPoint.new(date: date.to_date.iso8601, cost_cents: cost.to_i, total_tokens: tokens.to_i)
      end

    Result.new(time_series: points)
  end

  private

  attr_reader :company, :user, :scope, :since, :period

  def base_runs
    base = WorkflowRun.joins(:project).where(projects: { company_id: company.id }, created_at: since..)
    scope == "user" ? base.where(user:) : base
  end
end
