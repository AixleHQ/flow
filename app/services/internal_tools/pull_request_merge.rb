# frozen_string_literal: true

module InternalTools
  # The one pull-request action that changes the target branch. It needs the
  # connection to allow merging, and `expected_head_sha`: a push that lands
  # between the review and the merge makes it refuse rather than merge code
  # nobody reviewed (docs/design/bitbucket-integration.md §4.9).
  class PullRequestMerge < Base
    include Concerns::PullRequestContext

    tool do
      display_name "Pull Requests: Merge"
      description "Merge a pull request. `expected_head_sha` is the `head_sha` you reviewed (from " \
                  "pull_request_get): if the source branch has moved since, nothing is merged and you get a " \
                  "conflict with the current head. Approvals, branch rules and merge checks are never bypassed. " \
                  "Returns JSON: {merged, already_merged, pending, pull_request, operation_key}; `pending: true` " \
                  "means the host accepted the merge and has not finished it — read the pull request rather than " \
                  "calling this again."
      tags :pull_requests
      inject_when :pull_request_repositories_attached
      user_attachable false
      requires_integration :pull_requests
      unavailable_message Concerns::PullRequestContext::UNAVAILABLE
      destructive
      param :repository_id, type: :integer, description: Concerns::PullRequestContext::REPOSITORY_PARAM
      param :pull_request, type: :string, required: true, description: Concerns::PullRequestContext::PULL_REQUEST_PARAM
      param :expected_head_sha, type: :string, required: true, description: "The head commit you reviewed."
      param :strategy, type: :string, enum: %w[merge_commit squash fast_forward],
                       description: "How to merge. Defaults to the repository's own setting. On GitHub, fast_forward " \
                                     "rebases the commits onto the target (linear history, new commit ids)."
      param :delete_source_branch, type: :boolean, default: false, description: "Delete the source branch after merging."
      param :message, type: :string, description: "Merge (or squash) commit message."
      param :operation_key, type: :string, description: Concerns::PullRequestContext::OPERATION_KEY_PARAM
    end

    def execute
      pull_request_guard do
        repository, provider = resolve_target!
        unless repository.integration.pull_request_merge_enabled?
          raise PullRequests::Error.new("Merging is turned off for the #{repository.integration.name} connection",
                                        code: "permission_denied")
        end
        raise PullRequests::Error.new("expected_head_sha is required", code: "validation_failed") if params[:expected_head_sha].blank?

        number = provider.number_of(repository, params[:pull_request])
        payload = { repository_id: repository.id, pull_request: number, expected_head_sha: params[:expected_head_sha],
                    strategy: params[:strategy] }.compact
        with_write(repository, "merge", payload, number: number) do
          provider.merge(repository, number, expected_head_sha: params[:expected_head_sha].strip,
                                             strategy: params[:strategy].presence,
                                             delete_source_branch: params[:delete_source_branch] == true,
                                             message: params[:message].presence)
        end
      end
    end
  end
end
