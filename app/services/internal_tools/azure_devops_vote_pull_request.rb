# frozen_string_literal: true

module InternalTools
  # Voting is an agent expressing a review verdict as the connection's identity.
  # It is separate from completing the pull request, because an approval is not a
  # merge: branch policies decide whether an approved pull request may land.
  class AzureDevopsVotePullRequest < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Vote On Pull Request"
      description "Cast or reset this connection's review vote on an Azure Repos pull request. `reviewer_id` is an Azure identity id from azure_devops_list_pull_request_reviewers. Voting approve does NOT merge anything — completion is a separate tool and branch policies still apply. Returns the updated reviewer entry."
      tags :azure_devops
      requires_integration :azure_devops
      idempotent
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :pull_request_id, type: :integer, description: "Azure pull request id.", required: true
      param :reviewer_id, type: :string, description: "Azure identity id of the reviewer to vote as.", required: true
      param :vote, type: :string, description: "The verdict to record.", required: true,
                   enum: %w[approve approve_with_suggestions reset waiting_for_author reject]
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        result = AzureDevops::PullRequestService.new(integration).vote(
          repository, params[:pull_request_id],
          reviewer_id: params[:reviewer_id], vote: params[:vote]
        )
        success(result.to_json)
      end
    end
  end
end
