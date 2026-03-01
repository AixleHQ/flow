# frozen_string_literal: true

module ContextBuilders
  class AgentRole < Base
    def applicable?
      session.configured_agent_id.present?
    end

    def build
      agent = Agent.find_by(id: session.configured_agent_id)
      return [] unless agent

      [ section(
        tag: "agent-role",
        priority: :important,
        content: "## Your Role\n\n#{agent.to_system_prompt}",
        position_hint: :top
      ) ]
    end
  end
end
