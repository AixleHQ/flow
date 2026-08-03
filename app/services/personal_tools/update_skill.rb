# frozen_string_literal: true

module PersonalTools
  # Editing a hand-written skill. Registry skills are excluded: their content belongs
  # to the source they name, so an edit would silently diverge from it and the next
  # install would clobber it.
  #
  # Exists for the same reason CreateSkill does — an agent refining a skill it wrote
  # for its own future sessions is the obvious use, and a UI-only path would make
  # agents second-class.
  class UpdateSkill < Base
    tool do
      display_name "Update Skill"
      description "Rewrite a hand-written skill's SKILL.md (manual skills only)."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :skill_id, type: :integer, description: "Skill id to rewrite.", required: true
      param :content, type: :string,
                      description: "Full replacement SKILL.md: frontmatter with name and description, then instructions.",
                      required: true
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::SkillsPolicy, project: project)

      skill = ::Skill.visible_for_project(project).find_by(id: params[:skill_id])
      return error("Skill not found") if skill.blank?
      return error("Registry skills cannot be edited — remove it and add your own instead") unless skill.manual?

      result = ::Skills::SkillMarkdown.parse(params[:content])
      return error("Invalid SKILL.md: #{result.error_sentence}") unless result.valid?

      skill.update!(
        name: result.name,
        title: result.frontmatter["title"].presence || result.name,
        description: result.description,
        content: result.content
      )
      success(id: skill.id, name: skill.name, title: skill.title)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update skill: #{e.record.errors.full_messages.join(', ')}")
    end
  end
end
