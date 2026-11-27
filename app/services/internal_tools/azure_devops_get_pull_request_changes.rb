# frozen_string_literal: true

module InternalTools
  class AzureDevopsGetPullRequestChanges < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Get Pull Request Changes"
      description "List the files changed in one iteration of an Azure Repos pull request. This returns FILE METADATA ONLY — Azure does not serve a textual patch here, and the response says so. For the actual changes, read the files at the iteration's commits or run `git diff` in the checkout. Returns JSON: {iteration, changes: [{path, change_type}], diff_available: false, has_more, next_cursor}."
      tags :azure_devops
      requires_integration :azure_devops
      read_only
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :pull_request_id, type: :integer, description: "Azure pull request id.", required: true
      param :iteration, type: :integer, description: "Iteration number. Defaults to the latest."
      param :limit, type: :integer, description: "How many entries (default 50, max 100)."
      param :cursor, type: :string, description: "Pass `next_cursor` from a previous call."
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        result = AzureDevops::PullRequestService.new(integration).changes(
          repository, params[:pull_request_id],
          iteration: params[:iteration], limit: params[:limit], skip: params[:cursor].to_i
        )
        success(result.to_json)
      end
    end
  end
end
