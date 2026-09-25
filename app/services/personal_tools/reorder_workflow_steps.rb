# frozen_string_literal: true

module PersonalTools
  class ReorderWorkflowSteps < Base
    tool do
      display_name "Reorder Workflow Steps"
      description "Set the execution order of a workflow's steps by passing step ids in the desired order."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :step_ids, type: :array, description: "Step ids in the new order.", required: true, items: { type: "integer" }
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)

      ids = params[:step_ids]
      return error("step_ids must be a non-empty array") unless ids.is_a?(Array) && ids.any?

      steps_by_id = workflow.steps.not_deleted.index_by(&:id)
      unknown = ids.map(&:to_i) - steps_by_id.keys
      return error("Steps not in this workflow: #{unknown.join(', ')}") if unknown.any?

      Positions.reorder!(workflow.steps, ids)
      success(workflow_id: workflow.id, new_order: ids)
    end
  end
end
