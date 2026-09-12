# frozen_string_literal: true

module InternalTools
  # `expected_revision` becomes a JSON Patch `test` on /rev, so a concurrent
  # edit makes Azure reject the whole patch instead of letting this call
  # overwrite somebody else's change. Omitting it is a last-write-wins update.
  class AzureDevopsUpdateWorkItem < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Update Work Item"
      description "Update fields on an Azure Boards work item. Pass `expected_revision` — the `rev` you last read — so a concurrent edit is rejected rather than overwritten; on a mismatch this returns `conflict` with the current revision, and you should re-read before retrying. `state` must be one the type's process allows. Returns the updated work item as JSON."
      tags :azure_devops
      requires_integration :azure_devops
      param :integration_id, type: :integer, description: "Azure DevOps connection id.", required: true
      param :work_item_id, type: :integer, description: "Azure work item id.", required: true
      param :expected_revision, type: :integer, description: "The `rev` you last read. Strongly recommended."
      param :title, type: :string, description: "New title."
      param :description, type: :string, description: "New body."
      param :state, type: :string, description: "New state, from the type's allowed states."
      param :assigned_to, type: :string, description: "New assignee."
      param :area_path, type: :string, description: "New area path."
      param :iteration_path, type: :string, description: "New iteration path."
      param :tags, type: :string, description: "Semicolon-separated tags (replaces the set)."
      param :priority, type: :integer, description: "New priority."
    end

    FIELDS = %i[title description state assigned_to area_path iteration_path tags priority].freeze

    def execute
      azure_guard do
        integration = resolve_integration!
        fields = params.slice(*FIELDS.map(&:to_s)).symbolize_keys.compact_blank
        return error({ error: "validation_failed", message: "No fields to update" }.to_json) if fields.empty?

        result = AzureDevops::WorkItemService.new(integration).update(
          params[:work_item_id], fields: fields, expected_revision: params[:expected_revision]
        )
        success(result.to_json)
      end
    end
  end
end
