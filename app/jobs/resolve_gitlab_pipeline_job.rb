# frozen_string_literal: true

class ResolveGitlabPipelineJob < ApplicationJob
  queue_as :default

  # `repo_full_name` is what jobs queued before the delivery named its repository
  # carry; a job without either has nothing to route to.
  def perform(pipeline_id:, status:, repository_id: nil, repo_full_name: nil, mr_iid: nil)
    repository = Repository.find_by(id: repository_id) if repository_id
    return if repository.nil? && repo_full_name.blank?

    GateService.resolve_gitlab_pipeline(repository: repository, repo_full_name: repo_full_name || repository.full_name,
                                        pipeline_id: pipeline_id, status: status, mr_iid: mr_iid)
  end
end
