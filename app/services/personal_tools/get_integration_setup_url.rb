# frozen_string_literal: true

module PersonalTools
  class GetIntegrationSetupUrl < Base
    tool do
      display_name "Get Integration Setup URL"
      description "Return the URL of a project's integrations settings page, where the user connects an integration. " \
                  "Credentials are never handled over MCP — the user completes the connection in the browser."
      audience :user
      tags :integrations
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :provider, type: :string, description: "Integration provider to hint at.",
                       enum: %w[github gitlab linear coder slack]
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::IntegrationsPolicy, project: project)

      url = Rails.application.routes.url_helpers.company_project_integrations_url(
        project, host: Settings.domain, protocol: Settings.protocol
      )
      provider = params[:provider].presence
      hint = provider ? "Open this page and connect #{provider}." : "Open this page to manage integrations."
      success(project_id: project.id, provider: provider, setup_url: url, instructions: hint)
    end
  end
end
