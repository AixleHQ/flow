# frozen_string_literal: true

module InternalTools
  # Work item types and states come from the Azure PROJECT'S PROCESS, not from a
  # fixed vocabulary: Bug, Task, User Story, Issue and any custom type are not
  # interchangeable, and a state valid in one project is rejected in another.
  # Without this tool an agent guesses a type and gets a validation error it
  # cannot act on.
  class AzureDevopsListWorkItemTypes < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps List Work Item Types"
      description "List the work item types available in a connection's Azure project, with each type's allowed states and its always-required fields. Call this before creating or transitioning a work item — types and states are defined by the project's process, so they differ between projects. Returns JSON: {types: [{name, reference_name, states: [{name, category}], required_fields}]}."
      tags :azure_devops
      requires_integration :azure_devops
      read_only
      param :integration_id, type: :integer, description: "Azure DevOps connection id from azure_devops_list_connections.", required: true
    end

    def execute
      azure_guard do
        integration = resolve_integration!
        success({ types: AzureDevops::WorkItemService.new(integration).work_item_types }.to_json)
      end
    end
  end
end
