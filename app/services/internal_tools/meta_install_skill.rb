# frozen_string_literal: true

module InternalTools
  class MetaInstallSkill < Base
    include MetaToolHelpers

    def execute
      require_project_context!

      skill_id = params[:skill_id]
      return error("skill_id is required") if skill_id.blank?

      scope_type = params[:scope_type] || "Project"
      scope_id = params[:scope_id]

      scope_record = case scope_type
      when "Project"
        scope_id ||= target_project&.id
        Project.find(scope_id)
      when "Company"
        scope_id ||= target_project&.company_id
        Company.find(scope_id)
      else
        return error("Invalid scope_type: #{scope_type}")
      end

      skill = SkillsRegistryService.install(skill_id, scope: scope_record)

      broadcast_meta_activity(
        action: "installed_skill",
        entity_type: "Skill",
        entity_name: skill.title || skill.name,
        entity_id: skill.id
      )

      success({ id: skill.id, name: skill.name, title: skill.title, package: skill.package, source: skill.source }.to_json)
    rescue SkillsRegistryService::RegistryError => e
      error("Registry error: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to install skill: #{e.message}")
    end
  end
end
