# frozen_string_literal: true

module InternalTools
  class MetaCreateAgent < Base
    include MetaToolHelpers

    def execute
      require_project_context!

      scope_type = params[:scope_type] || "Project"
      scope_id = params[:scope_id]

      case scope_type
      when "Project"
        scope_id ||= target_project&.id
        scope_record = Project.find(scope_id)
      when "Company"
        scope_id ||= target_project&.company_id
        scope_record = Company.find(scope_id)
      else
        return error("Invalid scope_type: #{scope_type}. Must be 'Project' or 'Company'.")
      end

      agent = Agent.create!(
        scope: scope_record,
        name: params[:name],
        title: params[:title],
        persona: params[:persona],
        communication_style: params[:communication_style],
        principles: params[:principles],
        source: :custom
      )

      broadcast_meta_activity(
        action: "created_agent",
        entity_type: "Agent",
        entity_name: agent.title,
        entity_id: agent.id
      )

      success({
        id: agent.id,
        name: agent.name,
        title: agent.title,
        scope_type: agent.scope_type,
        scope_id: agent.scope_id
      }.to_json)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create agent: #{e.message}")
    end
  end
end
