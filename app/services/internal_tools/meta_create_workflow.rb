# frozen_string_literal: true

module InternalTools
  class MetaCreateWorkflow < Base
    include MetaToolHelpers

    def execute
      require_workflow_context!

      proj = target_project
      return error("No target project available") unless proj

      workflow = proj.workflows.create!(
        name: params[:name],
        description: params[:description],
        config: params[:config].presence || {}
      )

      store_in_shared_context("target_workflow_id", workflow.id)

      broadcast_meta_activity(
        action: "created_workflow",
        entity_type: "Workflow",
        entity_name: workflow.name,
        entity_id: workflow.id
      )

      success({
        id: workflow.id,
        name: workflow.name,
        description: workflow.description,
        scope_type: workflow.scope_type,
        scope_id: workflow.scope_id
      }.to_json)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create workflow: #{e.message}")
    end
  end
end
