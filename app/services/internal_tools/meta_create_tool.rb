# frozen_string_literal: true

module InternalTools
  class MetaCreateTool < Base
    include MetaToolHelpers

    def execute
      require_workflow_context!

      scope_record = resolve_scope

      tool = Tool.create!(
        scope: scope_record,
        name: params[:name],
        display_name: params[:display_name] || params[:name].titleize,
        description: params[:description],
        kind: :custom,
        execution_mode: params[:execution_mode] || "container",
        docker_image: params[:docker_image],
        input_schema: params[:input_schema] || {},
        command: params[:command]
      )

      broadcast_meta_activity(
        action: "created_tool",
        entity_type: "Tool",
        entity_name: tool.display_name,
        entity_id: tool.id
      )

      success({ id: tool.id, name: tool.name, display_name: tool.display_name }.to_json)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create tool: #{e.message}")
    end

    private

    def resolve_scope
      scope_type = params[:scope_type] || "Project"
      case scope_type
      when "Project"
        target_project
      when "Company"
        target_project&.company || Company.find(params[:scope_id])
      else
        target_project
      end
    end
  end
end
