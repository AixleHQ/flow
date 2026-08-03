# frozen_string_literal: true

module PersonalTools
  # Authoring a skill, as opposed to installing one from the registry
  # (see InstallSkill). Exists so an agent can do what the UI can — writing a
  # skill for its own future sessions is one of the more obvious uses of the
  # feature, and a UI-only path would make agents second-class here.
  class CreateSkill < Base
    tool do
      display_name "Create Skill"
      description "Register a hand-written skill in a project from SKILL.md content " \
                  "(frontmatter needs name and description)."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :content, type: :string,
                      description: "Full SKILL.md: YAML frontmatter with name and description, then instructions.",
                      required: true
    end

    def execute
      project = find_project!
      # `:manual?`, matching the web route this mirrors. Authoring is a strictly
      # larger trust grant than installing a third-party skill — it accepts arbitrary
      # prompt text — so if that policy is ever tightened, this tool must tighten too.
      authorize!(project, :manual?, policy: Web::Company::Projects::SkillsPolicy, project: project)

      result = ::Skills::SkillMarkdown.parse(params[:content])
      return error("Invalid SKILL.md: #{result.error_sentence}") unless result.valid?

      skill = project.skills.create!(
        name: result.name,
        title: result.frontmatter["title"].presence || result.name,
        description: result.description,
        content: result.content,
        origin: :manual
      )
      success(id: skill.id, name: skill.name, title: skill.title, origin: skill.origin.to_s)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create skill: #{e.record.errors.full_messages.join(', ')}")
    end
  end
end
