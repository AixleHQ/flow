# frozen_string_literal: true

# Single global GitHub App setup callback.
#
# The GitHub App "Setup URL" on GitHub.com is a fixed, app-wide value, so every
# installation — regardless of which project initiated it — lands here. The
# originating project is carried in the OAuth `state` param (`project:<id>`) and
# the callback always redirects back to that project's integrations page.
#
# Company-level integration management has been removed; there is no longer a
# company-wide integrations screen, so a stateless (no-project) callback is
# treated as a misroute and sent to the projects list.
class Web::Company::Integrations::GithubSetupController < Web::Company::ApplicationController
  # GitHub calls this endpoint without app-action context; authorization is
  # enforced in-action via `accessible_by?`.
  skip_before_action :dynamic_authorize!, only: :github_setup

  def github_setup
    target_project = resolve_github_setup_project(params[:state])
    installation_id = params[:installation_id]

    if installation_id.blank?
      redirect_to github_setup_redirect_path(target_project)
      return
    end

    if target_project.blank? || !target_project.accessible_by?(current_user)
      redirect_to company_projects_path,
                  alert: "Connect a GitHub integration from within a project."
      return
    end

    integration = Integration.find_or_build_github_for_installation(
      company: current_company,
      connected_by: current_user,
      project: target_project,
      installation_id: installation_id
    )
    integration.credentials_data = { installation_id: installation_id.to_s }

    begin
      info = Github::TokenService.new(integration).verify_installation
      integration.name = info[:account_login]
      integration.settings = {
        account_type: info[:account_type],
        target_type: info[:target_type]
      }
      integration.status = :active
    rescue Github::TokenService::ConfigurationError, Github::TokenService::AuthenticationError => e
      integration.name ||= "GitHub (unverified)"
      integration.status = :error
      integration.settings = { error: e.message }
    end

    integration.save
    redirect_to github_setup_redirect_path(target_project),
                notice: integration.active? ? "GitHub connected" : "GitHub connection failed — check integration status"
  end

  private

  def github_setup_redirect_path(project)
    project ? company_project_integrations_path(project) : company_projects_path
  end

  def resolve_github_setup_project(state)
    return nil if state.blank?

    match = state.to_s.match(/\Aproject:(\d+)\z/)
    return nil unless match

    current_company.projects.find_by(id: match[1].to_i)
  end
end
