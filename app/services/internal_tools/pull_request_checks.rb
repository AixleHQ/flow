# frozen_string_literal: true

module InternalTools
  class PullRequestChecks < Base
    include Concerns::PullRequestContext

    tool do
      display_name "Pull Requests: CI Checks"
      description "Read the CI status of a pull request's head commit. `state` is pending, passed, failed, or none " \
                  "when no CI has reported yet. To wait for CI to finish without polling, create a board gate " \
                  "instead. Returns JSON: {repository_id, checks: {state, head_sha, items: [{name, status, url}]}}."
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
        respond({ repository_id: repository.id, checks: provider.checks(repository, params[:pull_request]) })
      end
    end
  end
end
