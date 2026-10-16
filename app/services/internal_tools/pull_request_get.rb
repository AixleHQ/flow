# frozen_string_literal: true

module InternalTools
  class PullRequestGet < Base
    include Concerns::PullRequestContext

    tool do
      display_name "Pull Requests: Get"
      description "Read one pull request (GitLab merge request): title, description, state, draft, branches, " \
                  "head_sha (pass it to pull_request_merge as expected_head_sha), author, reviewers and whether " \
                  "the host considers it mergeable (null while it is still deciding). Returns JSON: " \
                  "{repository_id, pull_request}."
      tags :pull_requests
      inject_when :pull_request_repositories_attached
      user_attachable false
      requires_integration :pull_requests
      unavailable_message Concerns::PullRequestContext::UNAVAILABLE
      read_only
      param :repository_id, type: :integer, description: Concerns::PullRequestContext::REPOSITORY_PARAM
      param :pull_request, type: :string, required: true, description: Concerns::PullRequestContext::PULL_REQUEST_PARAM
    end

    def execute
      pull_request_guard do
        repository, provider = resolve_target!
        respond({ repository_id: repository.id, pull_request: provider.get(repository, params[:pull_request]) })
      end
    end
  end
end
