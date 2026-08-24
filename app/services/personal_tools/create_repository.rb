# frozen_string_literal: true

module PersonalTools
  class CreateRepository < Base
    tool do
      display_name "Create Repository"
      description "Attach a git repository to a project."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :full_name, type: :string, description: "owner/repo. Required unless public_url is given."
      param :public_url, type: :string,
                         description: "Public github.com/gitlab.com repository url. Attaches it read-only, cloned without credentials — use instead of integration_id for repositories nobody installed the app on."
      param :source_branch, type: :string, description: "Default branch."
      param :integration_id, type: :integer, description: "GitHub/GitLab integration id."
      param :description, type: :string, description: "Description."
      param :purpose, type: :string, description: "What the repo is used for."
      param :is_private, type: :boolean, description: "Private repo flag."
    end

    ATTRS = %w[full_name source_branch integration_id description purpose is_private].freeze

    def execute
      project = find_project!
      authorize!(project, :create?, policy: Web::Company::Projects::RepositoriesPolicy, project: project)
      repo = Repository.create!(attributes_for(project))
      success(id: repo.id, full_name: repo.full_name, source_branch: repo.source_branch,
              public_source: repo.public_source?)
    rescue PublicRepositoryService::Error => e
      error(e.message)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to add repository: #{e.message}")
    end

    private

    def attributes_for(project)
      return params.slice(*ATTRS).compact.merge(scope: project) if params["public_url"].blank?

      resolved = PublicRepositoryService.resolve(params["public_url"])
      attributes = resolved.to_repository_attributes
      attributes[:source_branch] = params["source_branch"] if params["source_branch"].present?
      attributes[:purpose] = params["purpose"] if params["purpose"].present?
      attributes.merge(scope: project)
    end
  end
end
