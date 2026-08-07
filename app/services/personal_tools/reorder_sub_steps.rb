# frozen_string_literal: true

module PersonalTools
  class ReorderSubSteps < Base
    tool do
      display_name "Reorder Sub-Steps"
      description "Set the order of a step's sub-steps by passing every sub-step id in the desired order. " \
                  "Read the step with get_workflow_step first — it reports the current ids and order."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :step_id, type: :integer, description: "Step id.", required: true
      param :sub_step_ids, type: :array, description: "Sub-step ids in the new order.", required: true,
            items: { type: "integer" }
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      step = find_step!(find_workflow!(project))

      ids = params[:sub_step_ids]
      return error("sub_step_ids must be a non-empty array") unless ids.is_a?(Array) && ids.any?

      by_id = step.sub_steps.active.index_by(&:id)
      ids = ids.map(&:to_i)
      unknown = ids - by_id.keys
      return error("Sub-steps not in this step: #{unknown.join(', ')}") if unknown.any?

      missing = by_id.keys - ids
      return error("Missing sub-step ids — pass every sub-step of the step: #{missing.join(', ')}") if missing.any?

      ActiveRecord::Base.transaction do
        ids.each_with_index { |id, idx| by_id.fetch(id).update_column(:position, idx + 1) }
      end
      success(step_id: step.id, new_order: ids)
    end
  end
end
