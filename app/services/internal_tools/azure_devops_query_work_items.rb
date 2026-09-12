# frozen_string_literal: true

module InternalTools
  # Structured filters, never caller-supplied WIQL. The query is assembled
  # server-side with the connection's Azure project pinned as a predicate and
  # every value escaped; a WIQL fragment from a caller cannot be made safe by
  # appending a project clause, because the fragment can close the clause itself.
  class AzureDevopsQueryWorkItems < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps Query Work Items"
      description "Find work items in a connection's Azure project using structured filters. Results are always restricted to that project. Returns JSON: {work_items: [{id, rev, type, title, state, assigned_to, tags, area_path}], total_matched, has_more, next_cursor}. Pass `next_cursor` back to page; ordering is by id descending and is stable."
      tags :azure_devops
      requires_integration :azure_devops
      read_only
      param :integration_id, type: :integer, description: "Azure DevOps connection id.", required: true
      param :ids, type: :array, description: "Specific work item ids.", items: { type: "integer" }
      param :type, type: :string, description: "Work item type name, e.g. Bug or User Story. See azure_devops_list_work_item_types."
      param :state, type: :string, description: "Exact state name, e.g. Active."
      param :assigned_to, type: :string, description: "Assignee, as the display name or email Azure shows."
      param :title_contains, type: :string, description: "Substring match on the title."
      param :tag, type: :string, description: "Single tag to match."
      param :open_only, type: :boolean, description: "Exclude Closed, Removed and Done."
      param :limit, type: :integer, description: "How many to return (default 50, max 100)."
      param :cursor, type: :string, description: "Pass `next_cursor` from a previous call."
    end

    def execute
      azure_guard do
        integration = resolve_integration!
        filters = params.slice(:ids, :type, :state, :assigned_to, :title_contains, :tag, :open_only)
                        .symbolize_keys
        result = AzureDevops::WorkItemService.new(integration).query(
          filters: filters, limit: params[:limit], cursor: params[:cursor]
        )
        success(result.to_json)
      end
    end
  end
end
