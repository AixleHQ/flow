# frozen_string_literal: true

module InternalTools
  class PullRequestChanges < Base
    include Concerns::PullRequestContext

    tool do
      display_name "Pull Requests: Changed Files"
      description "List the files a pull request changes, with their status (added, modified, removed, renamed) " \
                  "and line counts. For the diff itself, fetch the branches in your checkout and use git. " \
                  "Returns JSON: {repository_id, files: [{path, old_path, status, additions, deletions}], next_cursor}."
      tags :pull_requests
      inject_when :pull_request_repositories_attached
      user_attachable false
      requires_integration :pull_requests
      unavailable_message Concerns::PullRequestContext::UNAVAILABLE
      read_only
      param :repository_id, type: :integer, description: Concerns::PullRequestContext::REPOSITORY_PARAM
      param :pull_request, type: :string, required: true, description: Concerns::PullRequestContext::PULL_REQUEST_PARAM
      param :limit, type: :integer, description: Concerns::PullRequestContext::LIMIT_PARAM
      param :cursor, type: :string, description: Concerns::PullRequestContext::CURSOR_PARAM
    end

    def execute
      pull_request_guard do
        repository, provider = resolve_target!
        page = provider.changes(repository, params[:pull_request], cursor: params[:cursor], limit: page_limit)
        respond({ repository_id: repository.id, files: page.items, next_cursor: page.next_cursor })
      end
    end
  end
end
