# frozen_string_literal: true

module InternalTools
  class MetaListSkills < Base
    tool do
      display_name "Meta List Skills"
      description "List installed skills (from skills.sh registry) available for the project."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: [],
        properties: {}
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      proj = target_project
      return error("No target project available") unless proj

      skills = Skill.visible_for_project(proj)
                    .map do |s|
        { id: s.id, name: s.name, title: s.title, package: s.package, source: s.source, scope_type: s.scope_type }
      end

      success({ skills_count: skills.size, skills: skills }.to_json)
    end
  end
end
