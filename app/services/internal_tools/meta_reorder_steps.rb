# frozen_string_literal: true

module InternalTools
  class MetaReorderSteps < Base
    tool do
      display_name "Meta Reorder Steps"
      description "Reorder all steps in a workflow by providing ordered step IDs."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[step_ids],
        properties: {
          step_ids: {
            type: "array",
            items: {
              type: "integer"
            },
            description: "Ordered array of step IDs"
          },
          workflow_id: {
            type: "integer",
            description: "Workflow ID. Defaults to last created."
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      workflow = find_target_workflow!
      step_ids = params[:step_ids]

      return error("step_ids is required and must be an array") unless step_ids.is_a?(Array)

      ActiveRecord::Base.transaction do
        step_ids.each_with_index do |id, idx|
          step = workflow.steps.find(id)
          step.update_column(:position, idx + 1)
        end
      end

      broadcast_meta_activity(
        action: "reordered_steps",
        entity_type: "Workflow",
        entity_name: workflow.name,
        entity_id: workflow.id,
        details: { new_order: step_ids }
      )

      success({ workflow_id: workflow.id, new_order: step_ids }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Step not found: #{e.message}")
    rescue RuntimeError => e
      error(e.message)
    end
  end
end
