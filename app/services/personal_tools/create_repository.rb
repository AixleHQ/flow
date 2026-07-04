# frozen_string_literal: true

module PersonalTools
  class CreateRepository < Base
    tool do
      display_name "Create Repository"
      description "Attach a git repository to a project (requires company admin)."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :full_name, type: :string, description: "owner/repo.", required: true
      param :clone_url, type: :string, description: "Clone URL."
      param :source_branch, type: :string, description: "Default branch."
      param :integration_id, type: :integer, description: "GitHub/GitLab integration id."
      param :description, type: :string, description: "Description."
      param :purpose, type: :string, description: "What the repo is used for."
      param :is_private, type: :boolean, description: "Private repo flag."
    end

    ATTRS = %w[full_name clone_url source_branch integration_id description purpose is_private].freeze

    def execute
      project = find_project!
      authorize!(project, :create?, policy: Web::Company::Projects::RepositoriesPolicy, project: project)
      repo = Repository.create!(params.slice(*ATTRS).compact.merge(scope: project))
      success(id: repo.id, full_name: repo.full_name, source_branch: repo.source_branch)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to add repository: #{e.message}")
    end
  end
end
