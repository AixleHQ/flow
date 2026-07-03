# frozen_string_literal: true

module PersonalTools
  class DeleteWorkflowStep < Base
    tool do
      display_name "Delete Workflow Step"
      description "Delete a workflow step. Rejected if other steps depend on it."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :step_id, type: :integer, description: "Step id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)
      step = find_step!(workflow)

      dependents = workflow.steps.not_deleted.select { |s| s.depends_on_step_ids.include?(step.id) }
      if dependents.any?
        return error("Cannot delete step '#{step.name}' — other steps depend on it: #{dependents.map(&:name).join(', ')}")
      end

      name = step.name
      step.destroy!
      success(deleted_step_id: step.id, name: name, workflow_id: workflow.id)
    end
  end
end
