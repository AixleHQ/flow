# frozen_string_literal: true

module InternalTools
  class MetaInstallSkill < Base
    tool do
      display_name "Meta Install Skill"
      description "Install a skill from the skills.sh registry. Search first with meta_search_skills."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[skill_id],
        properties: {
          scope_id: {
            type: "integer",
            description: "Project ID. Default: current project"
          },
          skill_id: {
            type: "string",
            description: "Registry skill ID (e.g. mantinedev/skills/mantine-form)"
          },
          scope_type: {
            enum: %w[Project],
            type: "string",
            description: "Scope type. Always Project."
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      skill_id = params[:skill_id]
      return error("skill_id is required") if skill_id.blank?

      scope_id = params[:scope_id] || target_project&.id
      scope_record = Project.find(scope_id)

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
