# frozen_string_literal: true

class ProjectAnalyticsService
  PERIOD_DAYS = {
    "7d" => 7,
    "30d" => 30,
    "90d" => 90,
    "1y" => 365
  }.freeze

  Result = Struct.new(
    :total_sessions, :total_cost_cents, :total_tokens,
    :avg_cost_cents_per_session, :workflows_run,
    keyword_init: true
  )

  def initialize(project:, user:, scope:, period:)
    @project = project
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

    Result.new(
      total_sessions:,
      total_cost_cents:,
      total_tokens:,
      avg_cost_cents_per_session: avg_cost,
      workflows_run: base_workflow_runs.count
    )
  end

  private

  attr_reader :project, :user, :scope, :since

  def base_sessions
    scope_sessions.where(created_at: since..)
  end

  def scope_sessions
    case scope
    when "user"
      project.terminal_sessions.where(user:)
    when "company"
      TerminalSession
        .joins(:user)
        .where(users: { company_id: project.company_id })
    else
      project.terminal_sessions
    end
  end

  def usage_stats_for(sessions)
    row = UsageStatistic
      .where(terminal_session_id: sessions.select(:id))
      .pick(
        Arel.sql("COALESCE(SUM(cost_cents), 0)"),
        Arel.sql("COALESCE(SUM(tokens), 0)")
      )
    { cost_cents: row[0].to_i, tokens: row[1].to_i }
  end

  def base_workflow_runs
    case scope
    when "user"
      project.workflow_runs.where(user:, created_at: since..)
    when "company"
      WorkflowRun
        .joins(:project)
        .where(projects: { company_id: project.company_id })
        .where(created_at: since..)
    else
      project.workflow_runs.where(created_at: since..)
    end
  end
end
