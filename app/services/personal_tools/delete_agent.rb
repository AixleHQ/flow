# frozen_string_literal: true

module PersonalTools
  class DeleteAgent < Base
    tool do
      display_name "Delete Agent"
      description "Archive a project agent. It disappears from pickers and new sessions but keeps its history, and can be restored from the Agents page. Refused while a workflow step uses it."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :agent_id, type: :integer, description: "Agent id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :destroy?, policy: Web::Company::Projects::AgentsPolicy, project: project)
      agent = project.agents.unarchived.find_by(id: params[:agent_id])
      return error("Agent not found in this project") unless agent

      name = agent.name
      Versions.archive!(agent, actor: version_actor)
      success(archived_agent_id: agent.id, name: name)
    end
  end
end
