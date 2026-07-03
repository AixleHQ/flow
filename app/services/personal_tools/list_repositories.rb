# frozen_string_literal: true

module PersonalTools
  class ListRepositories < Base
    tool do
      display_name "List Repositories"
      description "List the git repositories attached to a project."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::RepositoriesPolicy, project: project)
      rows = project.repositories.limit(100).map do |r|
        { id: r.id, full_name: r.full_name, source_branch: r.source_branch, is_private: r.is_private,
          integration_id: r.integration_id, purpose: r.purpose }
      end
      success(project_id: project.id, repositories: rows)
    end
  end
end
