# frozen_string_literal: true

module InternalTools
  class MetaUpdateColumnBinding < Base
    include MetaToolHelpers

    def execute
      require_workflow_context!

      binding = ColumnWorkflowBinding.find(params[:binding_id])

      attrs = {}
      attrs[:trigger_mode] = params[:trigger_mode] if params.key?(:trigger_mode)
      attrs[:cooldown_seconds] = params[:cooldown_seconds] if params.key?(:cooldown_seconds)

      binding.update!(attrs)

      broadcast_meta_activity(
        action: "updated_column_binding",
        entity_type: "ColumnWorkflowBinding",
        entity_name: "#{binding.board_column.name} → #{binding.workflow.name}",
        entity_id: binding.id,
        details: { updated_fields: attrs.keys.map(&:to_s) }
      )

      success({
        id: binding.id,
        trigger_mode: binding.trigger_mode,
        cooldown_seconds: binding.cooldown_seconds
      }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Binding not found: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update binding: #{e.message}")
    end
  end
end
