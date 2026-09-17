# frozen_string_literal: true

module Insights
  # Lists completed Flow session usage for Insights pull sync.
  # Omits prompts, transcripts, events_data, secrets, and config values.
  class SessionUsagesQuery
    DEFAULT_LIMIT = 100
    MAX_LIMIT = 500
    EXPORTABLE_STATES = %w[finished failed].freeze

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(project:, since: nil, after_id: nil, limit: nil)
      @project = project
      @since = since
      @after_id = after_id
      @limit = normalize_limit(limit)
    end

    def call
      rows = base_scope.limit(@limit + 1).to_a
      has_more = rows.size > @limit
      rows = rows.first(@limit)

      {
        session_usages: rows.map { |session| serialize(session) },
        next_cursor: has_more ? cursor_for(rows.last) : nil
      }
    end

    private

    def base_scope
      scope = TerminalSession
              .joins(:usage_statistic)
              .includes(:usage_statistic, :user, :project)
              .where(project_id: @project.id)
              .where(state: EXPORTABLE_STATES)
              .where.not(session_type: "auth_setup")
              .where.not(finished_at: nil)
              .order(:finished_at, :id)

      scope = apply_since(scope)
      apply_after_id(scope)
    end

    def apply_since(scope)
      return scope if @since.blank?

      timestamp = Time.iso8601(@since)
      scope.where("terminal_sessions.finished_at >= ?", timestamp)
    rescue ArgumentError
      scope
    end

    def apply_after_id(scope)
      return scope if @after_id.blank?

      after = TerminalSession.find_by(id: @after_id, project_id: @project.id)
      return scope unless after&.finished_at

      scope.where(
        "(terminal_sessions.finished_at > ?) OR (terminal_sessions.finished_at = ? AND terminal_sessions.id > ?)",
        after.finished_at, after.finished_at, after.id
      )
    end

    def normalize_limit(limit)
      value = limit.to_i
      return DEFAULT_LIMIT if value <= 0

      [ value, MAX_LIMIT ].min
    end

    def cursor_for(session)
      { since: session.finished_at.iso8601(3), after_id: session.id }
    end

    def serialize(session)
      stat = session.usage_statistic
      Insights::SessionUsageSerializer.call(session: session, usage_statistic: stat)
    end
  end
end
