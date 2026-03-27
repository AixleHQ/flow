# frozen_string_literal: true

module InternalTools
  class MetaCreateSubStep < Base
    include MetaToolHelpers

    def execute
      require_workflow_context!

      step = Step.find(params[:step_id])
      position = params[:position] || (step.sub_steps.maximum(:position).to_i + 1)

      sub_step = step.sub_steps.create!(
        name: params[:name],
        position: position,
        description: params[:description],
        instructions: params[:instructions],
        required: params.fetch(:required, true)
      )

      broadcast_meta_activity(
        action: "created_sub_step",
        entity_type: "SubStep",
        entity_name: sub_step.name,
        entity_id: sub_step.id,
        details: { step_id: step.id, position: sub_step.position }
      )

      success({
        id: sub_step.id,
        step_id: step.id,
        name: sub_step.name,
        position: sub_step.position
      }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Step not found: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create sub-step: #{e.message}")
    end
  end
end
