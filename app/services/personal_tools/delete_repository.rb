# frozen_string_literal: true

module PersonalTools
  class DeleteRepository < Base
    tool do
      display_name "Delete Repository"
      description "Detach a repository from a project."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :repository_id, type: :integer, description: "Repository id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :destroy?, policy: Web::Company::Projects::RepositoriesPolicy, project: project)
      repo = project.repositories.find_by(id: params[:repository_id])
      return error("Repository not found in this project") unless repo

      name = repo.full_name
      repo.destroy
      success(deleted_repository_id: params[:repository_id].to_i, full_name: name)
    end
  end
end
