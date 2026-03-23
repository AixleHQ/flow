# frozen_string_literal: true

class ResolveGithubChecksJob < ApplicationJob
  queue_as :default

  def perform(repo_full_name:, pr_number:, conclusion:)
    WaitService.resolve_github_checks(
      repo_full_name: repo_full_name,
      pr_number: pr_number,
      conclusion: conclusion
    )
  end
end
