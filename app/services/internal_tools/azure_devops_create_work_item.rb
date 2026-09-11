# frozen_string_literal: true

module InternalTools
  class AzureDevopsCreateWorkItem < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Create Work Item"
      description "Create a work item in a connection's Azure project. `type` must be one the project's process defines — call azure_devops_list_work_item_types first, and check its required fields. `operation_key` is required and makes the call replay-safe. Returns JSON: {id, type, title, state, url}."
      tags :azure_devops
      requires_integration :azure_devops
      param :integration_id, type: :integer, description: "Azure DevOps connection id.", required: true
      param :type, type: :string, description: "Work item type name from azure_devops_list_work_item_types, e.g. Bug.", required: true
      param :title, type: :string, description: "Work item title.", required: true
      param :description, type: :string, description: "Body. Azure renders this as HTML."
      param :assigned_to, type: :string, description: "Assignee display name or email."
      param :area_path, type: :string, description: "Area path. Defaults to the project root."
      param :iteration_path, type: :string, description: "Iteration path."
      param :tags, type: :string, description: "Semicolon-separated tags."
      param :priority, type: :integer, description: "Priority (1-4 in most processes)."
      param :operation_key, type: :string, description: "Caller-chosen idempotency key. Reuse it verbatim when retrying.", required: true
    end

    FIELDS = %i[title description assigned_to area_path iteration_path tags priority].freeze

    def execute
      azure_guard do
        integration = resolve_integration!
        fields = params.slice(*FIELDS.map(&:to_s)).symbolize_keys.compact_blank
        payload = { type: params[:type] }.merge(fields)

        with_operation(integration, "create_work_item", payload) do
          AzureDevops::WorkItemService.new(integration).create(type: params[:type], fields: fields)
        end
      end
    end
  end
end
