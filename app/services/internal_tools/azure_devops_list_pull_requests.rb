# frozen_string_literal: true

module InternalTools
  class AzureDevopsListPullRequests < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps List Pull Requests"
      description "List pull requests in an attached Azure Repos repository. `repository_id` is the Aixle repository id from azure_devops_list_connections. Returns JSON: {pull_requests: [{id, title, status, is_draft, source_branch, target_branch, author, merge_status, url}], has_more, next_cursor}. Descriptions are truncated here — use azure_devops_get_pull_request for the full body."
      tags :azure_devops
      requires_integration :azure_devops
      read_only
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :state, type: :string, description: "active (default), completed, abandoned or all.",
                    enum: %w[active completed abandoned all]
      param :limit, type: :integer, description: "How many to return (default 50, max 100)."
      param :cursor, type: :string, description: "Pass `next_cursor` from a previous call."
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        result = AzureDevops::PullRequestService.new(integration).list(
          repository, state: params[:state].presence || "active",
          limit: params[:limit], skip: params[:cursor].to_i
        )
        success(result.to_json)
      end
    end
  end
end
