# frozen_string_literal: true

# Per-user agent-type breakdown. Mirrors CompanyAgentActivityService (joins
# usage_statistics for cost/tokens) but keys off a target user's sessions.
class UserAgentActivityService
  PERIOD_DAYS = { "7d" => 7, "30d" => 30, "90d" => 90, "1y" => 365 }.freeze
  USAGE_SESSION_TYPES = %w[agent_session workflow_step].freeze

  AgentBreakdown = Struct.new(:agent_type, :sessions, :cost_cents, :tokens, keyword_init: true)

  Result = Struct.new(:sessions_by_agent, keyword_init: true)

  def initialize(user:, company:, period:, project_id: nil)
    @user       = user
    @company    = company
    @period     = period.to_s
    @since      = PERIOD_DAYS.fetch(@period, 30).days.ago
    @project_id = project_id.presence
  end

  def call
    sessions_by_agent = base_sessions
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
        AgentBreakdown.new(agent_type:, sessions: count.to_i, cost_cents: cost.to_i, tokens: tokens.to_i)
      end
      .sort_by { |a| -a.sessions }

    Result.new(sessions_by_agent:)
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
