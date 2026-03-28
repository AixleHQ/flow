# frozen_string_literal: true

module InternalTools
  class MetaCreateColumnBinding < Base
    include MetaToolHelpers

    def execute
      require_project_context!

      column = BoardColumn.find(params[:column_id])
      workflow = Workflow.find(params[:workflow_id])

      if column.column_workflow_binding.present?
        existing = column.column_workflow_binding
        return error("Column '#{column.name}' already has a binding to workflow '#{existing.workflow.name}'. " \
                     "Delete it first with meta_delete_column_binding(binding_id: #{existing.id}).")
      end

      binding = ColumnWorkflowBinding.create!(
        board_column: column,
        workflow: workflow,
        trigger_mode: params[:trigger_mode] || "manual",
        cooldown_seconds: params[:cooldown_seconds] || 5
      )

      broadcast_meta_activity(
        action: "created_column_binding",
        entity_type: "ColumnWorkflowBinding",
        entity_name: "#{column.name} → #{workflow.name}",
        entity_id: binding.id,
        details: { column_id: column.id, workflow_id: workflow.id, trigger_mode: binding.trigger_mode }
      )

      success({
        id: binding.id,
        column_id: column.id,
        column_name: column.name,
        workflow_id: workflow.id,
        workflow_name: workflow.name,
        trigger_mode: binding.trigger_mode,
        cooldown_seconds: binding.cooldown_seconds
      }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Not found: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create binding: #{e.message}")
    end
  end
end
