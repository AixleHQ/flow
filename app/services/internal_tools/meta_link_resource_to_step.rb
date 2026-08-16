# frozen_string_literal: true

module InternalTools
  class MetaLinkResourceToStep < Base
    tool do
      display_name "Meta Link Resource to Step"
      description "Link a tool, skill, MCP server, asset, or config item (secret / environment " \
                  "variable) to a step. Linking a config item is what lets the step's agent read " \
                  "its value with `get_config_item` — attach one instead of writing a credential " \
                  "into the step instructions."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[step_id resource_type resource_id],
        properties: {
          step_id: {
            type: "integer",
            description: "Step ID"
          },
          resource_id: {
            type: "integer",
            description: "Resource ID to link"
          },
          resource_type: {
            enum: %w[tool skill mcp_server asset config_item],
            type: "string",
            description: "Resource type"
          }
        }
      })
    end

    include MetaToolHelpers

    RESOURCE_FIELDS = {
      "tool" => :tool_ids,
      "skill" => :skill_ids,
      "mcp_server" => :mcp_server_ids,
      "asset" => :asset_ids,
      "config_item" => :config_item_ids
    }.freeze

    def execute
      require_project_context!

      step = Step.find(params[:step_id])
      resource_type = params[:resource_type]
      resource_id = params[:resource_id]

      field = RESOURCE_FIELDS[resource_type]
      unless field
        return error("Invalid resource_type: #{resource_type}. Use: #{RESOURCE_FIELDS.keys.join(', ')}")
      end

      current_ids = step.send(field) || []
      unless current_ids.include?(resource_id)
        step.update!(field => current_ids + [ resource_id ])
      end

      broadcast_meta_activity(
        action: "linked_#{resource_type}",
        entity_type: resource_type.camelize,
        entity_name: "#{resource_type}##{resource_id}",
        entity_id: resource_id,
        details: { step_id: step.id, step_name: step.name }
      )

      success({ step_id: step.id, resource_type: resource_type, resource_id: resource_id, field => step.reload.send(field) }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Step not found: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to link resource: #{e.message}")
    end
  end
end
