# frozen_string_literal: true

module InternalTools
  class MetaListTools < Base
    include MetaToolHelpers

    def execute
      require_project_context!

      proj = target_project
      return error("No target project available") unless proj

      tools = Tool.where(kind: %i[custom system])
                  .where(scope_type: ["Company", "Project"], scope_id: [proj.company_id, proj.id])
                  .or(Tool.where(kind: %i[custom system], scope_type: nil))
                  .map do |t|
        { id: t.id, name: t.name, display_name: t.display_name, kind: t.kind, scope_type: t.scope_type }
      end

      success({ tools_count: tools.size, tools: tools }.to_json)
    end
  end
end
