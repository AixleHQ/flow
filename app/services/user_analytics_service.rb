# frozen_string_literal: true

# Per-user cross-project usage analytics. Mirrors CompanyAnalyticsService but keys
# off a resolved TARGET user (session ownership), not a company. Reads the user's
# terminal_sessions directly, so it must handle project-less sessions explicitly.
#
# Reconciliation invariant: build_project_breakdowns uses left_joins(:project) + a
# "(No project)" bucket so sum(project_breakdowns.{sessions,cost_cents,tokens}) always
# equals the summary totals, even for project-less agent_session/workflow_step rows.
class UserAnalyticsService
  PERIOD_DAYS = { "7d" => 7, "30d" => 30, "90d" => 90, "1y" => 365 }.freeze
  # Session types that represent real, billable usage (exclude auth_setup / tool_setup).
  USAGE_SESSION_TYPES = %w[agent_session workflow_step].freeze

  ProjectBreakdown = Struct.new(:project_id, :project_name, :sessions, :cost_cents, :tokens, keyword_init: true)

  Result = Struct.new(
    :total_sessions, :total_cost_cents, :total_tokens,
    :avg_cost_cents_per_session, :workflows_run, :project_breakdowns,
    keyword_init: true
  )

  def initialize(user:, period:, project_id: nil)
    @user       = user
    @period     = period.to_s
    @since      = PERIOD_DAYS.fetch(@period, 30).days.ago
    @project_id = project_id.presence
  end

  def call
    sessions = base_sessions
    stats    = usage_stats_for(sessions)
    total_sessions = sessions.count

    Result.new(
      total_sessions:,
      total_cost_cents: stats[:cost_cents],
      total_tokens: stats[:tokens],
      avg_cost_cents_per_session: total_sessions.positive? ? (stats[:cost_cents].to_f / total_sessions).round : 0,
      workflows_run: base_workflow_runs.count,
      project_breakdowns: build_project_breakdowns(sessions)
    )
  end

  private

  attr_reader :user, :period, :since, :project_id

  def base_sessions
    scope = user.terminal_sessions
                .where(created_at: since.., session_type: USAGE_SESSION_TYPES)
    project_id ? scope.where(project_id:) : scope
  end

  # Reuse the canonical cost/token expression from CompanyAnalyticsService.
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
    runs = WorkflowRun.for_user_in_period(user, since)
    project_id ? runs.where(project_id:) : runs
  end

  # CRITICAL difference from CompanyAnalyticsService: LEFT JOIN (not inner join) so
  # project-less billable sessions are grouped into a single "(No project)" bucket
  # (projects.id IS NULL), preserving the reconciliation invariant.
  def build_project_breakdowns(sessions)
    sessions
      .left_joins(:project)
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
      .map do |(id, name, sess_count, cost, tokens)|
        ProjectBreakdown.new(
          project_id: id,
          project_name: name || "(No project)",
          sessions: sess_count.to_i,
          cost_cents: cost.to_i,
          tokens: tokens.to_i
        )
      end
  end
end
