# frozen_string_literal: true

class CompanyAnalyticsService
  PERIOD_DAYS = {
    "7d" => 7,
    "30d" => 30,
    "90d" => 90,
    "1y" => 365
  }.freeze

  ProjectBreakdown = Struct.new(:project_id, :project_name, :sessions, :cost_cents, :tokens, keyword_init: true)

  Result = Struct.new(
    :total_sessions, :total_cost_cents, :total_tokens,
    :avg_cost_cents_per_session, :workflows_run, :project_breakdowns,
    keyword_init: true
  )

  def initialize(company:, user:, scope:, period:)
    @company = company
    @user = user
    @scope = scope.to_s
    @since = PERIOD_DAYS.fetch(period.to_s, 30).days.ago
  end

  def call
    sessions = base_sessions
    stats = usage_stats_for(sessions)

    total_sessions = sessions.count
    total_cost_cents = stats[:cost_cents]
    total_tokens = stats[:tokens]
    avg_cost = total_sessions.positive? ? (total_cost_cents.to_f / total_sessions).round : 0

    project_breakdowns = build_project_breakdowns(sessions)

    Result.new(
      total_sessions:,
      total_cost_cents:,
      total_tokens:,
      avg_cost_cents_per_session: avg_cost,
      workflows_run: base_workflow_runs.count,
      project_breakdowns:
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

  def usage_stats_for(sessions)
    row = UsageStatistic
      .where(terminal_session_id: sessions.select(:id))
      .pick(
        Arel.sql("COALESCE(SUM(cost_cents), 0)"),
        Arel.sql("COALESCE(NULLIF(SUM(input_tokens + output_tokens + cache_write_tokens + cache_read_tokens), 0), SUM(tokens), 0)")
      )
    { cost_cents: row[0].to_i, tokens: row[1].to_i }
  end

  def base_workflow_runs
    runs = WorkflowRun.joins(:project).where(projects: { company_id: company.id }, created_at: since..)
    scope == "user" ? runs.where(user:) : runs
  end

  def build_project_breakdowns(sessions)
    rows = sessions
      .joins(:project)
      .joins("LEFT JOIN usage_statistics ON usage_statistics.terminal_session_id = terminal_sessions.id")
      .group("projects.id", "projects.name")
      .order(Arel.sql("COALESCE(SUM(usage_statistics.cost_cents), 0) DESC"))
      .pluck(
        "projects.id",
        "projects.name",
        Arel.sql("COUNT(terminal_sessions.id)"),
        Arel.sql("COALESCE(SUM(usage_statistics.cost_cents), 0)"),
        Arel.sql("COALESCE(NULLIF(SUM(usage_statistics.input_tokens + usage_statistics.output_tokens + usage_statistics.cache_write_tokens + usage_statistics.cache_read_tokens), 0), SUM(usage_statistics.tokens), 0)")
      )
      .map do |(project_id, project_name, sess_count, cost, tokens)|
        ProjectBreakdown.new(
          project_id:,
          project_name:,
          sessions: sess_count.to_i,
          cost_cents: cost.to_i,
          tokens: tokens.to_i
        )
      end

    rows
  end
end
