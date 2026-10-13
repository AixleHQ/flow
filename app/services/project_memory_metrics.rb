# frozen_string_literal: true

class ProjectMemoryMetrics
  class Error < StandardError; end

  def initialize(project:, reviewer:)
    @project = project
    @reviewer = reviewer
  end

  def call(session_ids:)
    membership = @reviewer&.company_memberships&.active&.find_by(company_id: @project.company_id)
    permitted = membership && !membership.viewer? && (@project.owner_id == @reviewer.id || membership.admin?)
    raise Error, "Project memory metrics: forbidden" unless permitted && @project.accessible_by?(@reviewer)

    unless session_ids.is_a?(Array) && session_ids.size.between?(1, 100) &&
        session_ids.all? { |id| id.is_a?(Integer) && id.positive? }
      raise Error, "Project memory metrics: invalid selection"
    end
    ids = session_ids.uniq
    sessions = @project.terminal_sessions.where(company_id: @project.company_id, id: ids).includes(:usage_statistic).order(:id).to_a
    raise Error, "Project memory metrics: invalid selection" unless sessions.size == ids.size

    sessions.map { |session| row(session) }
  end

  private

  def row(session)
    stat = session.usage_statistic
    counters = session.metadata["project_memory"]
    counters = {} unless counters.is_a?(Hash)
    {
      session_id: session.id, agent_type: session.agent_type, state: session.state, cohort: nil,
      started_at: session.started_at&.iso8601, finished_at: session.finished_at&.iso8601,
      token_measurement_available: stat.present? && stat.total_tokens.positive? && session.agent_type != "kiro_cli",
      usage: stat && {
        source: stat.source, events_count: stat.events_count, models: stat.models,
        total_tokens: stat.total_tokens, input_tokens: stat.input_tokens, output_tokens: stat.output_tokens,
        cache_read_tokens: stat.cache_read_tokens, cache_write_tokens: stat.cache_write_tokens,
        cost_cents: stat.cost_cents,
        cost_cents_precise: stat.total_cents_precise&.positive? ? stat.total_cents_precise.to_s("F") : nil
      },
      memory: {
        retrieval_calls: counters.fetch("retrieval_calls", 0), retrieved_tokens_estimate: counters.fetch("retrieved_tokens", 0),
        captures: counters.fetch("captures", 0), failures: counters.fetch("failures", 0)
      }
    }
  end
end
