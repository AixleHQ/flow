# frozen_string_literal: true

module InternalTools
  class MetaUpdateStep < Base
    tool do
      display_name "Meta Update Step"
      description "Update an existing step's fields (name, instructions, agent_id, tool_ids, etc.)."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[step_id],
        properties: {
          name: {
            type: "string"
          },
          step_id: {
            type: "integer",
            description: "Step ID to update"
          },
          agent_id: {
            type: "integer"
          },
          tool_ids: {
            type: "array",
            items: {
              type: "integer"
            }
          },
          asset_ids: {
            type: "array",
            items: {
              type: "integer"
            }
          },
          skill_ids: {
            type: "array",
            items: {
              type: "integer"
            }
          },
          on_failure: {
            enum: %w[retry skip fail],
            type: "string"
          },
          max_retries: {
            type: "integer"
          },
          skip_policy: {
            enum: %w[never if_outputs_exist manual],
            type: "string"
          },
          instructions: {
            type: "string"
          },
          mcp_server_ids: {
            type: "array",
            items: {
              type: "integer"
            }
          },
          mount_repositories: {
            type: "boolean"
          },
          depends_on_step_ids: {
            type: "array",
            items: {
              type: "integer"
            }
          },
          allow_non_interactive: {
            type: "boolean"
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      step = Step.find(params[:step_id])

      updatable = %i[name instructions agent_id allow_non_interactive
                     skip_policy on_failure max_retries tool_ids skill_ids mcp_server_ids asset_ids
                     mount_repositories preferred_model bmad_enabled
                     input_asset_specs output_asset_specs depends_on_step_ids]

      attrs = {}
      updatable.each { |k| attrs[k] = params[k] if params.key?(k) }

      step.update!(attrs)

      broadcast_meta_activity(
        action: "updated_step",
        entity_type: "Step",
        entity_name: step.name,
        entity_id: step.id,
        details: { updated_fields: attrs.keys.map(&:to_s) }
      )

      success({ id: step.id, name: step.name, updated_fields: attrs.keys.map(&:to_s) }.to_json)
    rescue ActiveRecord::RecordNotFound => e
      error("Step not found: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update step: #{e.message}")
    end
  end
end
