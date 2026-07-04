# frozen_string_literal: true

module InternalTools
  class MetaDeleteColumnBinding < Base
    tool do
      display_name "Meta Delete Column Binding"
      description "Remove a workflow binding from a column."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[binding_id],
        properties: {
          binding_id: {
            type: "integer"
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

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
