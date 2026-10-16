# frozen_string_literal: true

module InternalTools
  class PullRequestListComments < Base
    include Concerns::PullRequestContext

    tool do
      display_name "Pull Requests: List Comments"
      description "Read the review comments on a pull request, thread by thread. A comment with `parent_id` is a " \
                  "reply in that comment's thread; `file_path` and `line` place an inline comment. Returns JSON: " \
                  "{repository_id, comments: [{id, parent_id, author, body, file_path, line, resolved, created_at}], " \
                  "next_cursor}."
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
        page = provider.list_comments(repository, params[:pull_request], cursor: params[:cursor], limit: page_limit)
        respond({ repository_id: repository.id, comments: page.items, next_cursor: page.next_cursor })
      end
    end
  end
end
