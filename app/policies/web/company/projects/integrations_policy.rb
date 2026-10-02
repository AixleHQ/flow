# frozen_string_literal: true

module Web
  module Company
    module Projects
      class IntegrationsPolicy < Web::Company::ApplicationPolicy
        def index? = project_accessible?
        def create? = manage_integrations?
        def update? = manage_integrations?
        def destroy? = manage_integrations?
        # Re-verifies a connection against the provider. It reads only, but it
        # spends the deployment's credential and reports provider diagnostics,
        # so it sits with the other management actions rather than with #index.
        def test_connection? = manage_integrations?
        # Binding an Azure organization is a connect, and it additionally
        # requires proving control of that organization to Azure itself.
        def azure_devops_inspect? = manage_integrations?
        def azure_devops_connect? = manage_integrations?
        def azure_devops_sign_in? = manage_integrations?
        def slack_oauth_start? = manage_integrations?
        def github_app_install? = manage_integrations?
        def jira_oauth_start? = manage_integrations?
        def jira_inspect? = manage_integrations?
        def jira_projects? = manage_integrations?
        def github_projects? = manage_integrations?
        def linear_oauth_start? = manage_integrations?
        def linear_inspect? = manage_integrations?
        def linear_teams? = manage_integrations?
        # Returns the webhook secret.
        def jira_webhook? = manage_integrations?

        private

        # Any member who can write to the project connects its integrations.
        # A company-wide install (Slack) is removed by a company admin only;
        # IntegrationsController#destroy enforces that, since this policy cannot
        # see which record is being removed.
        def manage_integrations?
          project_writable?
        end
      end
    end
  end
end
