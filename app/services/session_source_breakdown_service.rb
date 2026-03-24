# frozen_string_literal: true

class SessionSourceBreakdownService
  PERIOD_DAYS = {
    "7d" => 7,
    "30d" => 30,
    "90d" => 90,
    "1y" => 365
  }.freeze

  SOURCE_LABEL = {
    "agent_session" => "Standalone",
    "workflow_step" => "From Workflows",
    "auth_setup"    => "Auth Setup",
    "tool_setup"    => "Tool Setup"
  }.freeze

  SourceRow = Struct.new(:session_type, :label, :count, keyword_init: true)
  Result = Struct.new(:sources, keyword_init: true)

  def initialize(project:, user:, scope:, period:)
    @project = project
    @user    = user
    @scope   = scope.to_s
    @since   = PERIOD_DAYS.fetch(period.to_s, 30).days.ago
  end

  def call
    rows = base_sessions
      .group(:session_type)
      .order(Arel.sql("COUNT(*) DESC"))
      .pluck(:session_type, Arel.sql("COUNT(*)"))
      .map do |(session_type, count)|
        SourceRow.new(
          session_type: session_type,
          label: SOURCE_LABEL.fetch(session_type, session_type.humanize),
          count: count.to_i
        )
      end

    Result.new(sources: rows)
  end

  private

  attr_reader :project, :user, :scope, :since

  def base_sessions
    scope_sessions.where(created_at: since..)
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
