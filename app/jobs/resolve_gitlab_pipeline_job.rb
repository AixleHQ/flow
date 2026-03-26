# frozen_string_literal: true

class ResolveGitlabPipelineJob < ApplicationJob
  queue_as :default

  def perform(repo_full_name:, pipeline_id:, status:, mr_iid: nil)
    WaitService.resolve_gitlab_pipeline(
      repo_full_name: repo_full_name,
      pipeline_id: pipeline_id,
      status: status,
      mr_iid: mr_iid
    )
  end
end
