# frozen_string_literal: true

module PersonalTools
  # `list_agents` answers with id/name/title only, which is enough to attach an
  # agent to a step and nothing like enough to judge whether it is the right
  # one — or, for an agent re-reading its own configuration, to know what it was
  # told to be. Agents carry no `description` column: the text lives in
  # persona / principles / communication_style, so all three are returned in full.
  class GetAgent < Base
    tool do
      display_name "Get Agent"
      description "Return one project agent in full: persona, principles, communication style and icon."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :agent_id, type: :integer, description: "Agent id (see list_agents).", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::AgentsPolicy, project: project)

      agent = Agent.visible_for_project(project).find_by(id: params[:agent_id])
      return error("Agent not found in this project") unless agent

      success(id: agent.id, name: agent.name, title: agent.title, icon: agent.icon,
              persona: agent.persona, principles: agent.principles,
              communication_style: agent.communication_style,
              source: agent.source.to_s, scope: agent.scope_type)
    end
  end
end
