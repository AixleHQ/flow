# frozen_string_literal: true

module PersonalTools
  class CreateCustomTool < Base
    tool do
      display_name "Create Custom Tool"
      description "Create a custom (docker-image) tool in a project."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :name, type: :string, description: "Tool name (lowercase identifier).", required: true
      param :display_name, type: :string, description: "Human-readable name.", required: true
      param :docker_image, type: :string, description: "Docker image the tool runs.", required: true
      param :description, type: :string, description: "What the tool does."
      param :command, type: :string, description: "Command template ({{param}} placeholders)."
      param :input_schema, type: :object, description: "JSON Schema for the tool's parameters."
    end

    ATTRS = %w[name display_name docker_image description command input_schema].freeze

    def execute
      project = find_project!
      authorize!(project, :create?, policy: Web::Company::Projects::ToolsPolicy, project: project)
      tool = project.tools.create!(params.slice(*ATTRS).compact)
      success(id: tool.id, name: tool.name, display_name: tool.display_name, source: tool.source)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create tool: #{e.message}")
    end
  end
end
