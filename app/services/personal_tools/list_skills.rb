# frozen_string_literal: true

module PersonalTools
  class ListSkills < Base
    tool do
      display_name "List Skills"
      description "List the skills available in a project."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::SkillsPolicy, project: project)

      rows = Skill.visible_for_project(project).limit(100).map do |s|
        { id: s.id, name: s.name, title: s.title, description: s.description&.truncate(200),
          package: s.package, source: s.source }
      end
      success(project_id: project.id, skills: rows)
    end
  end
end
