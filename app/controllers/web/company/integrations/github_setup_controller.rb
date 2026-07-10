# frozen_string_literal: true

# Single global GitHub App setup callback.
#
# The GitHub App "Setup URL" on GitHub.com is a fixed, app-wide value, so every
# installation — regardless of which project initiated it — lands here. The
# originating project is carried in a SIGNED `state` param (Oauth::State: signed +
# 10-min TTL + single-use nonce + user pinning; minted by
# IntegrationsController#github_app_install) and the callback always redirects back
# to that project's integrations page. The legacy plaintext `project:<id>` state was
# replayable and forgeable (oauth-unification §7).
#
# Company-level integration management has been removed; there is no longer a
# company-wide integrations screen, so a stateless (no-project) callback is
# treated as a misroute and sent to the projects list.
class Web::Company::Integrations::GithubSetupController < Web::Company::ApplicationController
  # GitHub calls this endpoint without app-action context; authorization is
  # enforced in-action via `accessible_by?` + the signed-state user pin.
  skip_before_action :dynamic_authorize!, only: :github_setup

  def github_setup
    payload = Oauth::State.decode(params[:state])
    target_project = resolve_github_setup_project(payload)
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

    # Single-use + user pin: consume the nonce (rejects replays) and confirm the
    # signed initiating user matches the browser session (anti-CSRF, defense in depth).
    side = Oauth::State.consume(payload["nonce"])
    if side.nil? || side["user_id"] != current_user.id
      redirect_to github_setup_redirect_path(target_project),
                  alert: "GitHub setup link expired or already used — start the connection again."
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

  # Resolve the originating project from the verified, signed state payload. Returns
  # nil for a missing/tampered/expired state or a payload that isn't a github_setup
  # project state — the caller treats nil as a misroute.
  def resolve_github_setup_project(payload)
    return nil if payload.blank?
    return nil unless payload["provider"] == "github_setup"
    return nil unless payload["owner_type"] == "Project"

    current_company.projects.find_by(id: payload["owner_id"])
  end
end
