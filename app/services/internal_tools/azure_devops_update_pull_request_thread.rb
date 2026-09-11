# frozen_string_literal: true

module InternalTools
  class AzureDevopsUpdatePullRequestThread < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Resolve Pull Request Thread"
      description "Resolve or reopen a review conversation on an Azure Repos pull request by setting its status. Valid statuses: active (reopen), fixed, wontFix, closed, pending, byDesign. Returns the updated thread as JSON."
      tags :azure_devops
      requires_integration :azure_devops
      idempotent
      param :repository_id, type: :integer, description: "Aixle repository id.", required: true
      param :pull_request_id, type: :integer, description: "Azure pull request id.", required: true
      param :thread_id, type: :integer, description: "Thread to update.", required: true
      param :status, type: :string, description: "New thread status.", required: true,
                     enum: %w[active fixed wontFix closed pending byDesign]
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!
        result = AzureDevops::PullRequestService.new(integration).update_thread_status(
          repository, params[:pull_request_id], params[:thread_id], status: params[:status]
        )
        success(result.to_json)
      end
    end
  end
end
