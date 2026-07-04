# frozen_string_literal: true

module PersonalTools
  class UpdateRepository < Base
    tool do
      display_name "Update Repository"
      description "Update a project repository's branch, purpose or description (requires company admin)."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :repository_id, type: :integer, description: "Repository id.", required: true
      param :source_branch, type: :string, description: "Default branch."
      param :purpose, type: :string, description: "Purpose."
      param :description, type: :string, description: "Description."
    end

    ATTRS = %w[source_branch purpose description].freeze

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::RepositoriesPolicy, project: project)
      repo = project.repositories.find_by(id: params[:repository_id])
      return error("Repository not found in this project") unless repo

      attrs = params.slice(*ATTRS).reject { |_, v| v.nil? }
      return error("No fields to update") if attrs.empty?

      repo.update!(attrs)
      success(id: repo.id, full_name: repo.full_name, updated_fields: attrs.keys)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update repository: #{e.message}")
    end
  end
end
