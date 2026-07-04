# frozen_string_literal: true

module PersonalTools
  class ListAgents < Base
    tool do
      display_name "List Agents"
      description "List the agents available in a project (usable as a step's agent)."
      audience :user
      tags :workflows
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::AgentsPolicy, project: project)

      rows = Agent.visible_for_project(project).limit(100).map do |a|
        { id: a.id, name: a.name, title: a.title, scope: a.scope_type }
      end
      success(project_id: project.id, agents: rows)
    end
  end
end
