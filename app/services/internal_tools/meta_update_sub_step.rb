# frozen_string_literal: true

module InternalTools
  class MetaUpdateSubStep < Base
    tool do
      display_name "Meta Update Sub-Step"
      description "Update an existing sub-step's fields (name, instructions, position, required)."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[sub_step_id],
        properties: {
          name: {
            type: "string"
          },
          position: {
            type: "integer",
            description: "Position within the step"
          },
          required: {
            type: "boolean",
            description: "Must be completed for the step to finish"
          },
          instructions: {
            type: "string",
            description: "What the agent must do in this unit of work"
          },
          sub_step_id: {
            type: "integer",
            description: "Sub-step ID to update (see meta_get_workflow)"
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      sub_step = SubStep.find(params[:sub_step_id])
      attrs = %i[name instructions position required].each_with_object({}) do |key, acc|
        acc[key] = params[key] if params.key?(key)
      end
      return error("No fields to update") if attrs.empty?

      sub_step.update!(attrs)

      broadcast_meta_activity(
        action: "updated_sub_step",
        entity_type: "SubStep",
        entity_name: sub_step.name,
        entity_id: sub_step.id,
        details: { step_id: sub_step.step_id, updated_fields: attrs.keys.map(&:to_s) }
      )

      success({
        id: sub_step.id,
        step_id: sub_step.step_id,
        name: sub_step.name,
        position: sub_step.position,
        updated_fields: attrs.keys.map(&:to_s)
      }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Sub-step not found: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update sub-step: #{e.message}")
    end
  end
end
