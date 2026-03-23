# frozen_string_literal: true

class TopAgentsBySessionsService
  AgentStats = Struct.new(
    :rank, :name, :agent_type, :sessions_count, :total_cost_cents,
    keyword_init: true
  )

  def initialize(company, limit: 10)
    @company = company
    @limit = limit
  end

  def call
    rows = TerminalSession
      .joins(:configured_agent)
      .merge(Agent.belonging_to_company(company))
      .group("terminal_sessions.configured_agent_id", "agents.name", "agents.scope_type")
      .select(
        "terminal_sessions.configured_agent_id",
        "agents.name AS agent_name",
        "agents.scope_type AS agent_scope_type",
        "COUNT(*) AS sessions_count",
        "SUM(terminal_sessions.cost_cents) AS total_cost_cents"
      )
      .order("sessions_count DESC")
      .limit(limit)

    rows.each_with_index.map do |row, idx|
      AgentStats.new(
        rank: idx + 1,
        name: row.agent_name || "unknown",
        agent_type: row.agent_scope_type&.downcase || "unknown",
        sessions_count: row.sessions_count.to_i,
        total_cost_cents: row.total_cost_cents.to_i
      )
    end
  end

  private

  attr_reader :company, :limit
end
