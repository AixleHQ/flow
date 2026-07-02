# frozen_string_literal: true

module InternalTools
  class MetaListTools < Base
    tool do
      display_name "Meta List Tools"
      description "List custom and system tools available for the project."
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

      tools = Tool.not_deleted.where(kind: %i[custom system])
                  .where(scope_type: [ "Company", "Project" ], scope_id: [ proj.company_id, proj.id ])
                  .or(Tool.not_deleted.where(kind: %i[custom system], scope_type: nil))
                  .map do |t|
        { id: t.id, name: t.name, display_name: t.display_name, kind: t.kind, scope_type: t.scope_type }
      end

      success({ tools_count: tools.size, tools: tools }.to_json)
    end
  end
end
