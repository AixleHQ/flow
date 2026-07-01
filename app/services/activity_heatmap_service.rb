# frozen_string_literal: true

# Reusable GitHub-style contribution heatmap series: one session COUNT per calendar
# day over a fixed window. Used by both the profile Usage view (scope: a user's
# sessions) and the project analytics view (scope: a project's sessions, optionally
# narrowed to one participant).
#
# Divergence from AgentActivityService#activity_over_time: this deliberately does NOT
# re-apply the `agent_type IS NOT NULL` filter, so workflow_step sessions (which may
# have a null agent_type) still appear on the calendar as launched sessions.
class ActivityHeatmapService
  USAGE_SESSION_TYPES = %w[agent_session workflow_step].freeze
  DayCount = Struct.new(:date, :count, keyword_init: true)

  # scope: an ActiveRecord relation of terminal_sessions (already narrowed to a user,
  #   a project, or a project+participant by the caller).
  # days: window length (default 365 → a full contribution-year grid).
  def initialize(scope:, days: 365)
    @scope = scope
    @since = days.to_i.days.ago.beginning_of_day
  end

  def call
    day = Arel.sql("date_trunc('day', terminal_sessions.created_at)")
    @scope
      .where(created_at: @since.., session_type: USAGE_SESSION_TYPES)
      .group(day)
      .order(day)
      .pluck(day, Arel.sql("COUNT(terminal_sessions.id)"))
      .map { |d, c| DayCount.new(date: d.to_date.iso8601, count: c.to_i) }
  end
end
