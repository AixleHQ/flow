# frozen_string_literal: true

module PersonalTools
  class DeleteWorkflow < Base
    tool do
      display_name "Delete Workflow"
      description "Soft-delete a workflow. Rejected for system workflows or ones with active runs."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :destroy?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)

      return error("Cannot delete system workflow '#{workflow.name}'") if workflow.system?
      return error("Cannot delete '#{workflow.name}' — it has active runs") if workflow.has_active_runs?

      name = workflow.name
      workflow.soft_delete!
      success(deleted_workflow_id: workflow.id, name: name)
    end
  end
end
