# frozen_string_literal: true

module PersonalTools
  class ListProjectTools < Base
    tool do
      display_name "List Project Tools"
      description "List the tools available in a project (custom tools and attachable platform tools)."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::ToolsPolicy, project: project)

      rows = Tool.visible_for_project(project).ui_visible.limit(100).map do |t|
        { id: t.id, name: t.name, display_name: t.display_name, source: t.source, enabled: t.enabled }
      end
      success(project_id: project.id, tools: rows)
    end
  end
end
