# frozen_string_literal: true

module InternalTools
  # Linking is deliberately separate from transitioning: a linked pull request
  # must not close the work item by itself. Move the state with
  # azure_devops_update_work_item when that is actually what should happen.
  class AzureDevopsLinkWorkItem < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Link Work Item To Pull Request"
      description "Attach a pull request to an Azure Boards work item as an artifact link, so the fix is traceable from the task. This only creates the link — it never changes the work item's state. Re-linking an existing pair is a no-op. Both must be in this connection's Azure project. Returns the updated work item as JSON."
      tags :azure_devops
      requires_integration :azure_devops
      idempotent
      param :repository_id, type: :integer, description: "Aixle repository id holding the pull request.", required: true
      param :pull_request_id, type: :integer, description: "Azure pull request id.", required: true
      param :work_item_id, type: :integer, description: "Azure work item id.", required: true
      param :expected_revision, type: :integer, description: "The work item `rev` you last read."
      param :comment, type: :string, description: "Optional note stored on the link."
    end

    def execute
      azure_guard do
        repository, integration = resolve_repository!

        # Both ends are re-checked against this connection's scope before the
        # link is made: a work item id is unique per organization, not per
        # project, so one from a neighbouring project would otherwise link fine.
        pull_requests = AzureDevops::PullRequestService.new(integration)
        pull_requests.get(repository, params[:pull_request_id])

        result = AzureDevops::WorkItemService.new(integration).link_pull_request(
          params[:work_item_id],
          artifact_id: pull_requests.artifact_id(repository, params[:pull_request_id]),
          expected_revision: params[:expected_revision],
          comment: params[:comment]
        )
        success(result.to_json)
      end
    end
  end
end
