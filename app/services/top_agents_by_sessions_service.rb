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
    agent_ids = Agent.belonging_to_company(company).pluck(:id)

    rows = TerminalSession
      .where(configured_agent_id: agent_ids)
      .group(:configured_agent_id)
      .select(
        "configured_agent_id",
        "COUNT(*) AS sessions_count",
        "SUM(cost_cents) AS total_cost_cents"
      )
      .order("sessions_count DESC")
      .limit(limit)

    agents = Agent.where(id: rows.map(&:configured_agent_id)).index_by(&:id)

    rows.each_with_index.map do |row, idx|
      agent = agents[row.configured_agent_id]
      AgentStats.new(
        rank: idx + 1,
        name: agent&.name || "unknown",
        agent_type: agent&.scope_type&.downcase || "unknown",
        sessions_count: row.sessions_count.to_i,
        total_cost_cents: row.total_cost_cents.to_i
      )
    end
  end

  private

  attr_reader :company, :limit
end
