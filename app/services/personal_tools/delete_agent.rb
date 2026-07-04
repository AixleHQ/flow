# frozen_string_literal: true

module PersonalTools
  class DeleteAgent < Base
    tool do
      display_name "Delete Agent"
      description "Delete a project agent."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :agent_id, type: :integer, description: "Agent id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :destroy?, policy: Web::Company::Projects::AgentsPolicy, project: project)
      agent = project.agents.find_by(id: params[:agent_id])
      return error("Agent not found in this project") unless agent

      name = agent.name
      agent.destroy
      success(deleted_agent_id: params[:agent_id].to_i, name: name)
    end
  end
end
