# frozen_string_literal: true

module PersonalTools
  class InstallSkill < Base
    tool do
      display_name "Install Skill"
      description "Install a skill from the registry into a project (use search_skill_registry to find its id)."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :skill_id, type: :string, description: "Registry skill id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :create?, policy: Web::Company::Projects::SkillsPolicy, project: project)
      # Same install count the UI records, so the figure does not depend on which
      # path installed the skill.
      installs = CatalogSkill.find_by(registry_id: params[:skill_id].to_s)&.installs
      skill = SkillsRegistryService.install(params[:skill_id], scope: project, installs: installs)
      success(id: skill.id, name: skill.name, title: skill.title)
    rescue SkillsRegistryService::RegistryError => e
      error("Install failed: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      error("Install failed: #{e.record.errors.full_messages.join(', ')}")
    end
  end
end
