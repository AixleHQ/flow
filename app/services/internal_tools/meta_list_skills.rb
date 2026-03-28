# frozen_string_literal: true

module InternalTools
  class MetaListSkills < Base
    include MetaToolHelpers

    def execute
      require_project_context!

      proj = target_project
      return error("No target project available") unless proj

      skills = Skill.where(scope_type: ["Company", "Project"], scope_id: [proj.company_id, proj.id])
                    .or(Skill.where(kind: :internal))
                    .map do |s|
        { id: s.id, name: s.name, title: s.title, kind: s.kind, scope_type: s.scope_type }
      end

      success({ skills_count: skills.size, skills: skills }.to_json)
    end
  end
end
