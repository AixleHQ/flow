# frozen_string_literal: true

module InternalTools
  class AzureDevopsGetWorkItem < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Get Work Item"
      description "Read one Azure Boards work item: fields, current revision, relations and browser URL. The `rev` in the response is what azure_devops_update_work_item expects as `expected_revision`. Returns JSON."
      tags :azure_devops
      requires_integration :azure_devops
      read_only
      param :integration_id, type: :integer, description: "Azure DevOps connection id.", required: true
      param :work_item_id, type: :integer, description: "Azure work item id.", required: true
    end

    def execute
      azure_guard do
        integration = resolve_integration!
        success(AzureDevops::WorkItemService.new(integration).get(params[:work_item_id]).to_json)
      end
    end
  end
end
