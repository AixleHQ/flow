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
    signed_installation_id = payload&.dig("context", "installation_id")
    installation_id = signed_installation_id.presence || params[:installation_id]

    if installation_id.blank?
      redirect_to github_setup_redirect_path(target_project)
      return
    end

    if target_project.blank? && Oauth::State.expired?(params[:state])
      redirect_to company_projects_path,
                  alert: "The GitHub setup link expired — open the project's Integrations page and connect GitHub again."
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

    if Github::InstallationOwnership.enforced? && params[:code].blank?
      # Back from the authorization without a code (declined): asking again would loop.
      if signed_installation_id.present?
        redirect_to github_setup_redirect_path(target_project),
                    alert: "GitHub did not confirm your access to this installation — connect GitHub again."
      else
        redirect_to_github_authorization(target_project, installation_id)
      end
      return
    end

    # The project's company, not the session's: a user in two companies may
    # have switched away since starting the install.
    integration = Github::IntegrationService.new(
      company: target_project.company, connected_by: current_user, project: target_project
    ).create(installation_id: installation_id, oauth_code: params[:code])
    if integration.persisted? && integration.active?
      redirect_to github_setup_redirect_path(target_project), notice: "GitHub connected"
    else
      redirect_to github_setup_redirect_path(target_project),
                  alert: integration.errors.full_messages.to_sentence.presence ||
                         integration.settings&.dig("error") || "GitHub connection failed — check integration status"
    end
  end

  private

  def github_setup_redirect_path(project)
    project ? company_project_integrations_path(project) : company_projects_path
  end

  # The installation goes into the signed state: GitHub's authorization comes
  # back here with a code and our state, but not the installation.
  def redirect_to_github_authorization(project, installation_id)
    state = Oauth::State.encode(
      owner_type: "Project", owner_id: project.id, user_id: current_user.id,
      return_to: company_project_integrations_path(project), code_verifier: nil,
      provider: "github_setup", context: { "installation_id" => installation_id.to_s }
    )
    redirect_uri = company_integrations_github_setup_url(protocol: Settings.protocol, host: Settings.domain)
    # allow_other_host: github.com, built from deployment Settings — never user-supplied.
    redirect_to Github::InstallationOwnership.authorize_url(redirect_uri: redirect_uri, state: state),
                allow_other_host: true
  end

  # Resolve the originating project from the verified, signed state payload. Returns
  # nil for a missing/tampered/expired state or a payload that isn't a github_setup
  # project state — the caller treats nil as a misroute, or as expiry when the state
  # is ours but out of date.
  def resolve_github_setup_project(payload)
    return nil if payload.blank?
    return nil unless payload["provider"] == "github_setup"
    return nil unless payload["owner_type"] == "Project"

    current_company.projects.find_by(id: payload["owner_id"])
  end
end
