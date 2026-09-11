# frozen_string_literal: true

module InternalTools
  # The entry point for every other Azure tool: work-item tools require an
  # explicit `integration_id` rather than defaulting to one, so the agent needs
  # a way to see which connections exist and what each one is allowed to do.
  #
  # Returns the operation PROFILE (what this connection enables), not Azure's
  # ACLs. A capability listed here means the request will be sent; whether Azure
  # permits it is established by Azure's answer.
  class AzureDevopsListConnections < Base
    include Concerns::AzureDevopsContext

    tool do
      display_name "Azure DevOps List Connections"
      description "List this project's Azure DevOps connections: connection id, organization, selected Azure project, auth mode and enabled capabilities. Call this first — the work item tools need an explicit `integration_id`. Returns JSON: {connections: [{integration_id, organization, azure_project, azure_project_id, auth_mode, capabilities, status}]}. No credentials are ever returned."
      tags :azure_devops
      requires_integration :azure_devops
      read_only
      input_schema({ "type" => "object", "properties" => {}, "required" => [] })
    end

    def execute
      azure_guard do
        connections = eligible_integrations.map do |integration|
          {
            integration_id: integration.id,
            organization: integration.azure_organization_slug,
            azure_project: integration.azure_project_name,
            azure_project_id: integration.azure_project_id,
            # Surfaced because the two modes act as different identities: a PAT
            # connection acts as the token's owner, a service-principal one as
            # the application.
            auth_mode: integration.azure_auth_mode,
            identity: integration.settings&.dig("identity_display_name"),
            capabilities: integration.azure_enabled_capabilities,
            status: integration.status.to_s
          }.compact
        end

        repositories = Array(session&.repositories).select(&:azure_devops?).map do |repo|
          { repository_id: repo.id, name: repo.full_name, branch: repo.source_branch,
            integration_id: repo.integration_id }
        end

        success({ connections: connections, repositories: repositories }.to_json)
      end
    end
  end
end
