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

      workflows = Workflow.visible_for_project(project).order(:name).limit(100).to_a
      step_counts = Step.not_deleted.unscope(:order).where(workflow_id: workflows.map(&:id)).group(:workflow_id).count

      rows = workflows.map do |wf|
        { id: wf.id, name: wf.name, description: wf.description,
          scope: wf.scope_type, steps_count: step_counts.fetch(wf.id, 0) }
      end
      success(project_id: project.id, workflows: rows)
    end
  end
end
