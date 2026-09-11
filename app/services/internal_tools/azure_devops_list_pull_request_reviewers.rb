# frozen_string_literal: true

module InternalTools
  class AzureDevopsListPullRequestReviewers < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps List Pull Request Reviewers"
      description "List the reviewers on an Azure Repos pull request with their votes. Azure's votes are numeric — 10 approved, 5 approved with suggestions, 0 no vote, -5 waiting for the author, -10 rejected — and each reviewer's `vote_label` spells that out. `id` is the Azure identity id, which is what azure_devops_vote_pull_request takes."
      tags :azure_devops
      requires_integration :azure_devops
      read_only
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :pull_request_id, type: :integer, description: "Azure pull request id.", required: true
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        reviewers = AzureDevops::PullRequestService.new(integration)
                                                   .reviewers(repository, params[:pull_request_id])
        success({ reviewers: reviewers }.to_json)
      end
    end
  end
end
