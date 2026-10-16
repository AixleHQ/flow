# frozen_string_literal: true

module InternalTools
  class PullRequestList < Base
    include Concerns::PullRequestContext

    tool do
      display_name "Pull Requests: List"
      description "List pull requests (GitLab merge requests) of a GitLab or Bitbucket repository attached to this " \
                  "session, most recently updated first. Returns JSON: {repository_id, pull_requests: [{number, url, " \
                  "title, state, draft, source_branch, target_branch, head_sha, author, …}], next_cursor}."
      tags :pull_requests
      inject_when :pull_request_repositories_attached
      user_attachable false
      requires_integration :pull_requests
      unavailable_message Concerns::PullRequestContext::UNAVAILABLE
      read_only
      param :repository_id, type: :integer, description: Concerns::PullRequestContext::REPOSITORY_PARAM
      param :state, type: :string, enum: %w[open merged closed all], default: "open", description: "Which pull requests."
      param :source_branch, type: :string, description: "Only pull requests from this branch."
      param :limit, type: :integer, description: Concerns::PullRequestContext::LIMIT_PARAM
      param :cursor, type: :string, description: Concerns::PullRequestContext::CURSOR_PARAM
    end

    def execute
      pull_request_guard do
        repository, provider = resolve_target!(ref: nil)
        page = provider.list(repository, state: params[:state].presence || "open", source_branch: params[:source_branch],
                                         cursor: params[:cursor], limit: page_limit)
        respond({ repository_id: repository.id, pull_requests: page.items, next_cursor: page.next_cursor })
      end
    end
  end
end
