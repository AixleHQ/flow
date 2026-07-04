# frozen_string_literal: true

module PersonalTools
  class UpdateCustomTool < Base
    tool do
      display_name "Update Custom Tool"
      description "Update a custom tool's fields. Platform tools cannot be edited."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :tool_id, type: :integer, description: "Tool id.", required: true
      param :display_name, type: :string, description: "Name."
      param :docker_image, type: :string, description: "Docker image."
      param :description, type: :string, description: "Description."
      param :command, type: :string, description: "Command template."
      param :enabled, type: :boolean, description: "Enabled flag."
      param :input_schema, type: :object, description: "JSON Schema."
    end

    ATTRS = %w[display_name docker_image description command enabled input_schema].freeze

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::ToolsPolicy, project: project)
      tool = project.tools.db_source.not_deleted.find_by(id: params[:tool_id])
      return error("Custom tool not found in this project") unless tool

      attrs = params.slice(*ATTRS).reject { |_, v| v.nil? }
      return error("No fields to update") if attrs.empty?

      tool.update!(attrs)
      success(id: tool.id, name: tool.name, updated_fields: attrs.keys)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update tool: #{e.message}")
    end
  end
end
