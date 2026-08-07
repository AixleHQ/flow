# frozen_string_literal: true

module PersonalTools
  # `list_skills` truncates description to 200 characters and never carries
  # content, so "attach this skill or not" is decided from one line. This reads
  # the whole thing — including the SKILL.md body an agent would actually run on.
  class GetSkill < Base
    tool do
      display_name "Get Skill"
      description "Return one project skill in full, including its complete SKILL.md content. " \
                  "Skill content can be thousands of tokens — narrow the choice with list_skills " \
                  "first and fetch this only for the skill you are actually deciding on."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :skill_id, type: :integer, description: "Skill id (see list_skills).", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::SkillsPolicy, project: project)

      skill = ::Skill.visible_for_project(project).find_by(id: params[:skill_id])
      return error("Skill not found in this project") unless skill

      success(id: skill.id, name: skill.name, title: skill.title,
              description: skill.description, content: skill.content,
              package: skill.package, source: skill.source, source_url: skill.source_url,
              origin: skill.origin.to_s)
    end
  end
end
