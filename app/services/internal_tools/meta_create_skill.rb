# frozen_string_literal: true

module InternalTools
  class MetaCreateSkill < Base
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
        return error("Invalid scope_type: #{scope_type}")
      end

      skill = Skill.create!(
        scope: scope_record,
        name: params[:name],
        title: params[:title],
        content: params[:content],
        description: params[:description],
        kind: :custom
      )

      broadcast_meta_activity(
        action: "created_skill",
        entity_type: "Skill",
        entity_name: skill.title || skill.name,
        entity_id: skill.id
      )

      success({ id: skill.id, name: skill.name, title: skill.title }.to_json)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create skill: #{e.message}")
    end
  end
end
