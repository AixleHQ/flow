# frozen_string_literal: true

module PersonalTools
  class UninstallSkill < Base
    tool do
      display_name "Uninstall Skill"
      description "Archive a project skill. New sessions stop getting it; it keeps its history and can be restored from the Skills page. Refused while a workflow uses it."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :skill_id, type: :integer, description: "Skill id (project-scoped).", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :destroy?, policy: Web::Company::Projects::SkillsPolicy, project: project)
      skill = Skill.for_project(project).unarchived.find_by(id: params[:skill_id])
      return error("Project skill not found") unless skill

      name = skill.name
      Versions.archive!(skill, actor: version_actor)
      success(archived_skill_id: skill.id, name: name)
    end
  end
end
