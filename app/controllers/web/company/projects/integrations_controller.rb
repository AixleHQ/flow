# frozen_string_literal: true

class Web::Company::Projects::IntegrationsController < Web::Company::Projects::ApplicationController
  def index
    integrations = Integration.visible_for_project(current_project)
                              .includes(:connected_by)
                              .order(created_at: :desc)

    render inertia: "Projects/Integrations/IntegrationsPage", props: {
      project: project_props,
      integrations: integrations.map { |i| IntegrationResource.new(i).to_h }
    }
  end

  def create
    provider = params[:provider].to_s

    integration = case provider
    when "github"
      Github::IntegrationService.new(
        company: current_company,
        connected_by: current_user,
        project: current_project
      ).create(installation_id: params[:installation_id].to_s)
    when "gitlab"
      Gitlab::IntegrationService.new(
        company: current_company,
        connected_by: current_user,
        project: current_project
      ).create(personal_access_token: params[:personal_access_token].to_s)
    when "coder"
      Coder::IntegrationService.new(
        company: current_company,
        connected_by: current_user,
        project: current_project
      ).create(
        coder_url:        params[:coder_url].to_s,
        session_token:    params[:session_token].to_s,
        default_template: params[:default_template].presence,
        machine_prefix:   params[:machine_prefix].presence,
        lock_ttl_minutes: params[:lock_ttl_minutes].presence
      )
    end
    # Slack connects via OAuth (see #slack_oauth_start + Web::Integrations::SlackOauthController),
    # not this paste-credentials path.

    if integration.nil?
      redirect_to company_project_integrations_path(current_project), alert: "Unsupported provider: #{provider}"
    elsif integration.persisted? && integration.active?
      redirect_to company_project_integrations_path(current_project), notice: "#{provider.capitalize} integration connected"
    else
      error_msg = integration.settings&.dig("error") || "Failed to connect #{provider.capitalize}"
      redirect_to company_project_integrations_path(current_project), alert: error_msg
    end
  end

  def destroy
    integration = Integration.for_project(current_project).find(params[:id])
    integration.destroy
    redirect_to company_project_integrations_path(current_project), notice: "Integration removed"
  end

  # Kick off the Slack OAuth install for this project: redirect to Slack's consent
  # screen with a signed `state` that carries the project. Slack redirects back to
  # the deployment-wide callback (Web::Integrations::SlackOauthController#callback).
  def slack_oauth_start
    # allow_other_host: the target is Slack's hardcoded authorize URL built from
    # deployment Settings.slack.* — never user-supplied.
    redirect_to Slack::Oauth.authorize_url(project: current_project, user: current_user), allow_other_host: true
  end

  # Kick off a GitHub App installation for this project. The GitHub App "Setup URL"
  # is app-wide, so we carry the originating project in a SIGNED `state` (Oauth::State:
  # signed + 10-min TTL + single-use nonce + user pinning) instead of the old
  # plaintext `project:<id>` (replayable, forgeable — oauth-unification §7). GitHub
  # echoes `state` back to the deployment-wide callback (GithubSetupController).
  def github_app_install
    slug = Settings.github.app_slug
    if slug.blank?
      redirect_to company_project_integrations_path(current_project), alert: "GitHub App is not configured"
      return
    end

    state = Oauth::State.encode(
      owner_type: "Project",
      owner_id: current_project.id,
      user_id: current_user.id,
      return_to: company_project_integrations_path(current_project),
      code_verifier: nil,          # GitHub App setup has no PKCE code exchange
      provider: "github_setup"
    )
    # allow_other_host: github.com install URL built from deployment Settings — never user-supplied.
    redirect_to "https://github.com/apps/#{slug}/installations/new?state=#{CGI.escape(state)}",
                allow_other_host: true
  end
end
