# frozen_string_literal: true

module InternalTools
  # Comments live behind their own API, not in System.History. Reading the
  # history field instead silently drops comments, which is why this is a
  # separate tool rather than a field on the work item.
  class AzureDevopsListWorkItemComments < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps List Work Item Comments"
      description "Read the comments on an Azure Boards work item, oldest first, with authors and timestamps. Returns JSON: {comments: [{id, author, text, created_at}], has_more, next_cursor}."
      tags :azure_devops
      requires_integration :azure_devops
      read_only
      param :integration_id, type: :integer, description: "Azure DevOps connection id.", required: true
      param :work_item_id, type: :integer, description: "Azure work item id.", required: true
      param :limit, type: :integer, description: "How many to return (default 50, max 100)."
      param :cursor, type: :string, description: "Pass `next_cursor` from a previous call."
    end

    def execute
      azure_guard do
        integration = resolve_integration!
        result = AzureDevops::WorkItemService.new(integration).comments(
          params[:work_item_id], limit: params[:limit], cursor: params[:cursor]
        )
        success(result.to_json)
      end
    end
  end
end
