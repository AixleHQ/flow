# frozen_string_literal: true

module PersonalTools
  class ListWorkflows < Base
    tool do
      display_name "List Workflows"
      description "List the workflows visible in a project, with step counts."
      audience :user
      tags :workflows
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)

      rows = Workflow.visible_for_project(project).order(:name).limit(100).map do |wf|
        { id: wf.id, name: wf.name, description: wf.description,
          scope: wf.scope_type, steps_count: wf.steps.not_deleted.count }
      end
      success(project_id: project.id, workflows: rows)
    end
  end
end
