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

      # Custom (db) tools scoped to the project's company/project, plus system
      # (code) tools exposed to users. Builder meta_* tools set user_attachable
      # false and are excluded (source replaced the old `kind` column: db=custom,
      # code=system).
      scoped_tools = Tool.not_deleted.where(scope_type: "Company", scope_id: proj.company_id)
                         .or(Tool.not_deleted.where(scope_type: "Project", scope_id: proj.id))
      system_tools = Tool.not_deleted.where(source: "code", user_attachable: true, scope_type: nil)

      tools = scoped_tools.or(system_tools)
                  .map do |t|
        { id: t.id, name: t.name, display_name: t.display_name,
          kind: (t.db_source? ? "custom" : "system"), scope_type: t.scope_type }
      end

      success({ tools_count: tools.size, tools: tools }.to_json)
    end
  end
end
