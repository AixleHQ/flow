# frozen_string_literal: true

module InternalTools
  class MetaDeleteSubStep < Base
    tool do
      display_name "Meta Delete Sub-Step"
      description "Delete a sub-step from a step. A sub-step that already has runs is soft-deleted " \
                  "so past run history stays readable."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[sub_step_id],
        properties: {
          sub_step_id: {
            type: "integer",
            description: "Sub-step ID to delete (see meta_get_workflow)"
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      sub_step = SubStep.find(params[:sub_step_id])
      name = sub_step.name
      step_id = sub_step.step_id
      sub_step.destroy

      broadcast_meta_activity(
        action: "deleted_sub_step",
        entity_type: "SubStep",
        entity_name: name,
        entity_id: sub_step.id,
        details: { step_id: step_id }
      )

      success({ deleted: true, sub_step_name: name, step_id: step_id, soft_deleted: sub_step.deleted? }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Sub-step not found: #{e.message}")
    end
  end
end
