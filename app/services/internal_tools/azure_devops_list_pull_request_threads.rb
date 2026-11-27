# frozen_string_literal: true

module InternalTools
  # Azure's review model is threads of comments, not a flat list. A reply needs
  # the THREAD id, so this returns threads with their comments nested rather
  # than flattening them — flattening is what makes an agent answer the wrong
  # conversation.
  class AzureDevopsListPullRequestThreads < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps List Pull Request Threads"
      description "Read the review conversations on an Azure Repos pull request. Each thread carries its status, its file and line when it is an inline comment, and its comments in order. Reply with azure_devops_reply_pull_request_thread using the thread's `id` — a comment id alone is not enough to reply. Returns JSON: {threads: [{id, status, file_path, right_line, comments: [{id, author, content}]}], has_more}."
      tags :azure_devops
      requires_integration :azure_devops
      read_only
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :pull_request_id, type: :integer, description: "Azure pull request id.", required: true
      param :limit, type: :integer, description: "How many threads (default 50, max 100)."
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        result = AzureDevops::PullRequestService.new(integration).list_threads(
          repository, params[:pull_request_id], limit: params[:limit]
        )
        success(result.to_json)
      end
    end
  end
end
