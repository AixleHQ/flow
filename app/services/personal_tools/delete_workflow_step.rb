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
      param :base_version, type: :integer, description: "The workflow version you read (current_version_number). A newer one means someone else saved since, and the change is refused."
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
      Versions.save!(workflow, actor: version_actor, base_version: base_version) { step.destroy! }
      success(deleted_step_id: step.id, name: name, workflow_id: workflow.id)
    end
  end
end
