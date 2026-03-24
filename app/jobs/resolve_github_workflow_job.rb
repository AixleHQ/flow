# frozen_string_literal: true

class ResolveGithubWorkflowJob < ApplicationJob
  queue_as :default

  def perform(repo_full_name:, run_id:, conclusion:)
    WaitService.resolve_github_workflow(
      repo_full_name: repo_full_name,
      run_id: run_id,
      conclusion: conclusion
    )
  end
end
