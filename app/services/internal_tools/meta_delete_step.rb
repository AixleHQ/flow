# frozen_string_literal: true

module InternalTools
  class MetaDeleteStep < Base
    tool do
      display_name "Meta Delete Step"
      description "Delete a step from a workflow. Fails if other steps depend on it."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[step_id],
        properties: {
          step_id: {
            type: "integer",
            description: "Step ID to delete"
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      step = Step.find(params[:step_id])

      # Check no other steps depend on this one
      dependents = step.workflow.steps.not_deleted.select { |s| s.depends_on_step_ids.include?(step.id) }
      if dependents.any?
        names = dependents.map(&:name).join(", ")
        return error("Cannot delete step '#{step.name}' — other steps depend on it: #{names}")
      end

      name = step.name
      step.destroy!

      broadcast_meta_activity(
        action: "deleted_step",
        entity_type: "Step",
        entity_name: name,
        entity_id: params[:step_id]
      )

      success({ deleted: true, step_name: name }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Step not found: #{e.message}")
    end
  end
end
