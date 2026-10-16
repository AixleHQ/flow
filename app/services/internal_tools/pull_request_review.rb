# frozen_string_literal: true

module InternalTools
  class PullRequestReview < Base
    include Concerns::PullRequestContext

    tool do
      display_name "Pull Requests: Review"
      description "Approve a pull request, withdraw an approval, or request changes, with an optional comment. " \
                  "GitLab takes approve and unapprove only; ask for changes there with pull_request_add_comment. On GitHub, " \
                  "unapprove dismisses this connection's latest approval. " \
                  "Returns JSON: {reviewer, verdict, submitted_at, operation_key}."
      tags :pull_requests
      inject_when :pull_request_repositories_attached
      user_attachable false
      requires_integration :pull_requests
      unavailable_message Concerns::PullRequestContext::UNAVAILABLE
      param :repository_id, type: :integer, description: Concerns::PullRequestContext::REPOSITORY_PARAM
      param :pull_request, type: :string, required: true, description: Concerns::PullRequestContext::PULL_REQUEST_PARAM
      param :verdict, type: :string, required: true, enum: %w[approve unapprove request_changes],
                      description: "The review verdict."
      param :body, type: :string, description: "A comment posted with the review."
      param :operation_key, type: :string, description: Concerns::PullRequestContext::OPERATION_KEY_PARAM
    end

    def execute
      pull_request_guard do
        repository, provider = resolve_target!
        number = provider.number_of(repository, params[:pull_request])
        payload = { repository_id: repository.id, pull_request: number, verdict: params[:verdict], body: params[:body] }.compact
        with_write(repository, "review", payload, number: number) do
          provider.review(repository, number, verdict: params[:verdict], body: params[:body].presence)
        end
      end
    end
  end
end
