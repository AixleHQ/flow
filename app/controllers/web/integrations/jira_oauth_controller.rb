# frozen_string_literal: true

# Deployment-wide callback of Aixle's Atlassian OAuth app. The project comes
# from the signed, single-use Oauth::State, which also pins the initiating user;
# the connection is bound only to a project that user can reach.
class Web::Integrations::JiraOauthController < Web::ApplicationController
  before_action :require_auth
  skip_before_action :redirect_super_admin_to_admin_panel, raise: false

  def callback
    state = Oauth::State.decode(params[:state])
    unless state && state["provider"] == Jira::Oauth::PROVIDER && state["user_id"] == current_user.id
      return redirect_to(root_path, alert: "Invalid or expired Jira authorization")
    end

    project = Project.for_user(current_user).find_by(id: state["owner_id"])
    return redirect_to(root_path, alert: "Invalid or expired Jira authorization") if project.nil?

    path = company_project_integrations_path(project)
    # A cancel leaves the nonce alone, so the person can try again.
    return redirect_to(path, alert: "Jira connection was cancelled") if params[:error].present?
    return redirect_to(path, alert: "This Jira authorization link was already used") if Oauth::State.consume(state["nonce"]).nil?
    unless Web::Company::Projects::IntegrationsPolicy.new(ProjectContext.new(current_user, {}, project: project), project).create?
      return redirect_to(path, alert: "You cannot connect integrations in this project")
    end

    integration = Jira::IntegrationService.new(company: project.company, connected_by: current_user, project: project)
                                          .connect_oauth(code: params[:code].to_s)
    if integration.active?
      redirect_to path, notice: "#{integration.name} reconnected"
    else
      redirect_to company_project_integrations_path(project, jira_setup: integration.id), notice: "Pick the Jira projects to connect"
    end
  rescue Jira::Error, Jira::IntegrationService::ConfigurationError => e
    redirect_to company_project_integrations_path(project), alert: "Jira connection failed: #{e.message}"
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end
end
