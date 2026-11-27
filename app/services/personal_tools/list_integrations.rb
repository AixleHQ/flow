# frozen_string_literal: true

module PersonalTools
  # The ids `integration_ids` / `base_integration_ids` take (docs/design/session-integrations.md
  # §5.1): the integrations a workflow or a step may attach, i.e. the project's own and the
  # company's, of a provider whose tools take an integration. Nothing secret: no credentials.
  class ListIntegrations < Base
    tool do
      display_name "List Integrations"
      description "List the integrations a workflow or a step can attach: Coder, Slack, Teams and Azure DevOps " \
                  "integrations of the project and of its company, with id, name, provider, scope and status. " \
                  "Attach them with integration_ids on a step or base_integration_ids on a workflow; a session " \
                  "gets only the integrations attached to it. Integrations are connected on the project's " \
                  "Integrations page, not here."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :show?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      rows = TenantScope.owned(Integration, project: project).attachable.order(:provider, :id)
      success(project_id: project.id, integrations: rows.map { |integration| view(integration) })
    end

    private

    def view(integration)
      { id: integration.id, name: integration.name, provider: integration.provider.to_s,
        scope: integration.project_id ? "project" : "company", status: integration.status.to_s,
        host: integration.coder? ? integration.coder_host : nil }.compact
    end
  end
end
