# frozen_string_literal: true

module PersonalTools
  class UninstallSkill < Base
    tool do
      display_name "Uninstall Skill"
      description "Remove a project-scoped skill."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :skill_id, type: :integer, description: "Skill id (project-scoped).", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :destroy?, policy: Web::Company::Projects::SkillsPolicy, project: project)
      skill = Skill.for_project(project).find_by(id: params[:skill_id])
      return error("Project skill not found") unless skill

      name = skill.name
      skill.destroy
      success(uninstalled_skill_id: params[:skill_id].to_i, name: name)
    end
  end
end
