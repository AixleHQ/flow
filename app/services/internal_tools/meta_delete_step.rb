# frozen_string_literal: true

module InternalTools
  class MetaDeleteStep < Base
    include MetaToolHelpers

    def execute
      require_workflow_context!

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
