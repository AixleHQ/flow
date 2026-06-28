# frozen_string_literal: true

module InternalTools
  class MetaLinkResourceToStep < Base
    include MetaToolHelpers

    RESOURCE_FIELDS = {
      "tool" => :tool_ids,
      "skill" => :skill_ids,
      "mcp_server" => :mcp_server_ids,
      "asset" => :asset_ids
    }.freeze

    def execute
      require_project_context!

      step = Step.find(params[:step_id])
      resource_type = params[:resource_type]
      resource_id = params[:resource_id]

      field = RESOURCE_FIELDS[resource_type]
      return error("Invalid resource_type: #{resource_type}. Use: tool, skill, mcp_server, asset") unless field

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
