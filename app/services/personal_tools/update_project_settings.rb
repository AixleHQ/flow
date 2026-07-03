# frozen_string_literal: true

module PersonalTools
  class UpdateProjectSettings < Base
    tool do
      display_name "Update Project Settings"
      description "Update a project's name, description, artifacts language or state."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :name, type: :string, description: "Project name."
      param :description, type: :string, description: "Project description."
      param :preferred_artifacts_language, type: :string, description: "Artifacts language."
      param :state, type: :string, description: "Project state."
    end

    ATTRS = %w[name description preferred_artifacts_language state].freeze

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::SettingsPolicy, project: project)
      attrs = params.slice(*ATTRS).reject { |_, v| v.nil? }
      return error("No fields to update") if attrs.empty?

      project.update!(attrs)
      success(id: project.id, name: project.name, updated_fields: attrs.keys)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update project: #{e.message}")
    end
  end
end
