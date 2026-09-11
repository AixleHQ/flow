# frozen_string_literal: true

module InternalTools
  # The one agent action that changes the default branch. Three things guard it,
  # and none of them is optional:
  #
  # - it needs the `pull_requests.complete` capability, which a new connection
  #   does NOT get — merging is not something to acquire by accepting a form's
  #   defaults;
  # - `expected_commit` is required, so a push that lands between reading the
  #   pull request and completing it makes Azure refuse rather than merge code
  #   the agent never saw;
  # - branch policies are never bypassed, and a successful response is not proof
  #   of a merge — Azure completes asynchronously, so the result says `completed`
  #   only after a re-read confirms it.
  class AzureDevopsCompletePullRequest < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Complete Pull Request"
      description "Complete (merge) an Azure Repos pull request. Requires the connection to enable `pull_requests.complete`, which is off by default. `expected_commit` is the `last_merge_source_commit` you read from the pull request — Azure refuses if the source branch has moved since, which is what stops this merging code you did not review. Branch policies are never bypassed; check azure_devops_get_pull_request_policies first. Returns JSON with `completed: true` only once a re-read confirms the merge; `pending: true` means Azure accepted the request and it has not landed — re-read rather than calling this again."
      tags :azure_devops
      requires_integration :azure_devops
      destructive
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :pull_request_id, type: :integer, description: "Azure pull request id.", required: true
      param :expected_commit, type: :string, required: true,
                              description: "The pull request's `last_merge_source_commit` as you last read it."
      param :merge_strategy, type: :string, description: "How to merge. Defaults to squash.",
                             enum: %w[squash noFastForward rebase rebaseMerge], default: "squash"
      param :delete_source_branch, type: :boolean, description: "Delete the source branch after merging.",
                                   default: false
      param :commit_message, type: :string, description: "Merge commit message."
      param :operation_key, type: :string, required: true,
                            description: "Caller-chosen idempotency key. Reuse it verbatim when retrying."
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        payload = {
          repository_id: repository.id, pull_request_id: params[:pull_request_id],
          expected_commit: params[:expected_commit], merge_strategy: params[:merge_strategy] || "squash"
        }

        with_operation(integration, "complete_pull_request", payload) do
          AzureDevops::PullRequestService.new(integration).complete(
            repository, params[:pull_request_id],
            expected_commit: params[:expected_commit],
            merge_strategy: params[:merge_strategy] || "squash",
            delete_source_branch: params[:delete_source_branch] == true,
            commit_message: params[:commit_message]
          )
        end
      end
    end
  end
end
