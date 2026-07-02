# frozen_string_literal: true

module InternalTools
  class MetaCreateWorkflow < Base
    tool do
      display_name "Meta Create Workflow"
      description "Create a new workflow in the target project. Stores workflow_id in shared context for subsequent tools."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[name],
        properties: {
          name: {
            type: "string",
            description: "Workflow name"
          },
          config: {
            type: "object",
            description: "Optional workflow config (base_tool_ids, etc.)"
          },
          project_id: {
            type: "integer",
            description: "Target project ID. Defaults to current project."
          },
          description: {
            type: "string",
            description: "Workflow description"
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      proj = target_project
      return error("No target project available") unless proj

      workflow = proj.workflows.create!(
        name: params[:name],
        description: params[:description],
        config: params[:config].presence || {}
      )

      store_in_context("target_workflow_id", workflow.id)

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
