# frozen_string_literal: true

module InternalTools
  class MetaListAgents < Base
    include MetaToolHelpers

    def execute
      require_project_context!

      proj = target_project
      return error("No target project available") unless proj

      agents = Agent.visible_for_project(proj).map do |a|
        { id: a.id, name: a.name, title: a.title, scope_type: a.scope_type }
      end

      success({ agents_count: agents.size, agents: agents }.to_json)
    end
  end
end
