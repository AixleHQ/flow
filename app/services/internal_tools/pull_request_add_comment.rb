# frozen_string_literal: true

module InternalTools
  class PullRequestAddComment < Base
    include Concerns::PullRequestContext

    tool do
      display_name "Pull Requests: Add Comment"
      description "Comment on a pull request. Pass `file_path` and `line` (a line of the new version of the file) " \
                  "for an inline comment, or `reply_to` (a comment id from pull_request_list_comments) to answer " \
                  "in that comment's thread. Returns JSON: {id, parent_id, author, body, file_path, line, " \
                  "created_at, operation_key}."
      tags :pull_requests
      inject_when :pull_request_repositories_attached
      user_attachable false
      requires_integration :pull_requests
      unavailable_message Concerns::PullRequestContext::UNAVAILABLE
      param :repository_id, type: :integer, description: Concerns::PullRequestContext::REPOSITORY_PARAM
      param :pull_request, type: :string, required: true, description: Concerns::PullRequestContext::PULL_REQUEST_PARAM
      param :body, type: :string, required: true, description: "Comment text (Markdown)."
      param :file_path, type: :string, description: "Repository-relative path, for an inline comment."
      param :line, type: :integer, description: "Line in the new version of `file_path`."
      param :reply_to, type: :string, description: "Id of the comment to reply to."
      param :operation_key, type: :string, description: Concerns::PullRequestContext::OPERATION_KEY_PARAM
    end

    def execute
      pull_request_guard do
        repository, provider = resolve_target!
        number = provider.number_of(repository, params[:pull_request])
        payload = { repository_id: repository.id, pull_request: number, body: params[:body],
                    file_path: params[:file_path], line: params[:line], reply_to: params[:reply_to] }.compact
        with_write(repository, "add_comment", payload, number: number) do
          provider.add_comment(repository, number, body: params[:body], file_path: params[:file_path].presence,
                                                   line: params[:line], reply_to: params[:reply_to].presence)
        end
      end
    end
  end
end
