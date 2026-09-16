# frozen_string_literal: true

module InternalTools
  class AzureDevopsAddWorkItemComment < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Add Work Item Comment"
      description "Add a comment to an Azure Boards work item. `operation_key` is required and makes the call replay-safe: the same key returns the original result instead of posting the comment twice. Returns JSON: {id, created_at}. Posting a comment BUMPS the work item's `rev`, so a revision read before commenting is stale immediately after — re-read before an update that pins `expected_revision`."
      tags :azure_devops
      inject_when :azure_integration_connected
      user_attachable false
      requires_integration :azure_devops
      param :integration_id, type: :integer, description: "Azure DevOps connection id.", required: true
      param :azure_project_id, type: :string, description: "Azure project id. Required when the connection covers more than one; call azure_devops_list_connections to see them."
      param :work_item_id, type: :integer, description: "Azure work item id.", required: true
      param :text, type: :string, description: "Comment text (markdown).", required: true
      param :operation_key, type: :string, description: "Caller-chosen idempotency key. Reuse it verbatim when retrying.", required: true
    end

    def execute
      azure_guard do
        integration = resolve_integration!
        payload = { work_item_id: params[:work_item_id], text: params[:text] }

        with_operation(integration, "add_work_item_comment", payload) do
          AzureDevops::WorkItemService.new(integration).add_comment(
            params[:work_item_id], text: params[:text], project_id: resolve_project_id!(integration)
          )
        end
      end
    end
  end
end
