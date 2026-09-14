# frozen_string_literal: true

module InternalTools
  # Membership on a review, and whether that membership is binding.
  #
  # It was introduced believing voting required it — Azure adds the voter itself,
  # so it does not. What it is actually for is putting SOMEONE ELSE on a review,
  # and making an approval required rather than optional.
  #
  # `required: false` by default. A required reviewer is a branch-policy-level
  # obligation on other people's work, which is not something to acquire from a
  # parameter's default.
  class AzureDevopsAddPullRequestReviewer < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Add Pull Request Reviewer"
      description "Add a reviewer to an Azure Repos pull request. `reviewer_id` is an Azure identity id — a user or a group. Use it to put someone on the review, or to make an existing reviewer's approval required. Voting does not need it — azure_devops_vote_pull_request adds the identity itself. Re-adding an existing reviewer keeps their current vote. Optional by default; `required: true` makes the reviewer's approval mandatory, which blocks completion until they vote. Returns the reviewer entry: {id, display_name, vote, required}."
      tags :azure_devops
      inject_when :azure_repositories_attached
      user_attachable false
      requires_integration :azure_devops
      idempotent
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :pull_request_id, type: :integer, description: "Azure pull request id.", required: true
      param :reviewer_id, type: :string, description: "Azure identity id of the user or group to add.", required: true
      param :required, type: :boolean,
                       description: "Make the approval mandatory. Defaults to false — an optional reviewer.",
                       default: false
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        result = AzureDevops::PullRequestService.new(integration).add_reviewer(
          repository, params[:pull_request_id],
          reviewer_id: params[:reviewer_id], required: params[:required] == true
        )
        success(result.to_json)
      end
    end
  end
end
