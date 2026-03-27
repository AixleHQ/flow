# frozen_string_literal: true

module InternalTools
  class MetaDeleteColumnBinding < Base
    include MetaToolHelpers

    def execute
      require_workflow_context!

      binding = ColumnWorkflowBinding.find(params[:binding_id])
      desc = "#{binding.board_column.name} → #{binding.workflow.name}"

      binding.destroy!

      broadcast_meta_activity(
        action: "deleted_column_binding",
        entity_type: "ColumnWorkflowBinding",
        entity_name: desc,
        entity_id: params[:binding_id]
      )

      success({ deleted: true, description: desc }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Binding not found: #{e.message}")
    end
  end
end
