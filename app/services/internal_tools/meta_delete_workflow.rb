# frozen_string_literal: true

module InternalTools
  class MetaDeleteWorkflow < Base
    include MetaToolHelpers

    def execute
      require_project_context!

      workflow = Workflow.find(params[:workflow_id])

      if workflow.system?
        return error("Cannot delete system workflow '#{workflow.name}'")
      end

      if workflow.has_active_runs?
        return error("Cannot delete workflow '#{workflow.name}' — it has active runs")
      end

      name = workflow.name
      workflow.soft_delete!

      broadcast_meta_activity(
        action: "deleted_workflow",
        entity_type: "Workflow",
        entity_name: name,
        entity_id: params[:workflow_id]
      )

      success({ deleted: true, workflow_name: name }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Workflow not found: #{e.message}")
    rescue ActiveRecord::RecordNotDestroyed => e
      error(e.message)
    end
  end
end
