# frozen_string_literal: true

module InternalTools
  class MetaListAgents < Base
    tool do
      display_name "Meta List Agents"
      description "List agents visible for the target project."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: [],
        properties: {}
      })
    end

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
