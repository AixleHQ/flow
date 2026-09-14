# frozen_string_literal: true

module InternalTools
  class AzureDevopsListBuilds < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps List Builds"
      description "List recent Azure Pipelines builds for a connection, newest first, optionally filtered to one repository and branch. `status` is the lifecycle (notStarted, inProgress, completed) and `result` is the verdict — a completed build with no result is not a pass. Returns JSON: {builds: [{id, build_number, status, result, definition, branch, commit, url}]}."
      tags :azure_devops
      inject_when :azure_integration_connected
      user_attachable false
      requires_integration :azure_devops
      read_only
      param :integration_id, type: :integer, description: "Azure DevOps connection id.", required: true
      param :azure_project_id, type: :string, description: "Azure project id. Required when the connection covers more than one; call azure_devops_list_connections to see them."
      param :repository_id, type: :integer, description: "Aixle repository id, to list only its builds."
      param :branch, type: :string, description: "Branch name, e.g. main."
      param :limit, type: :integer, description: "How many builds (default 25, max 100)."
    end

    def execute
      azure_guard do
        integration = resolve_integration!
        repository = nil

        if params[:repository_id].present?
          repository, repository_integration = resolve_repository!
          unless repository_integration.id == integration.id
            return error({ error: "validation_failed",
                           message: "That repository belongs to a different Azure connection" }.to_json)
          end
        end

        builds = AzureDevops::BuildService.new(integration)
                                          .list(repository: repository, branch: params[:branch],
                                                limit: params[:limit] || 25,
                                                project_id: resolve_project_id!(integration))
        success({ builds: builds }.to_json)
      end
    end
  end
end
