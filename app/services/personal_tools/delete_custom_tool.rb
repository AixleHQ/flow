# frozen_string_literal: true

module PersonalTools
  class DeleteCustomTool < Base
    tool do
      display_name "Delete Custom Tool"
      description "Soft-delete a custom tool."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :tool_id, type: :integer, description: "Tool id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :destroy?, policy: Web::Company::Projects::ToolsPolicy, project: project)
      tool = project.tools.db_source.not_deleted.find_by(id: params[:tool_id])
      return error("Custom tool not found in this project") unless tool

      name = tool.name
      tool.soft_delete!
      success(deleted_tool_id: tool.id, name: name)
    end
  end
end
