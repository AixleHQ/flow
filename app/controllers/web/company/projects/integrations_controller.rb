# frozen_string_literal: true

class Web::Company::Projects::IntegrationsController < Web::Company::Projects::ApplicationController
  def index
    integrations = Integration.visible_for_project(current_project)
                              .includes(:connected_by, :azure_devops_installation)
                              .order(created_at: :desc)

    render inertia: "Projects/Integrations/IntegrationsPage", props: {
      project: project_props,
      integrations: integrations.map { |i| IntegrationResource.new(i).to_h },
      azure_devops: azure_devops_props
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
    when "azure_devops"
      return create_azure_devops
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

  # Edits provider settings on an already-connected integration. Scoped with
  # `for_project` like #destroy: a company-wide integration is shared by every
  # project, so it is not editable from one project's page.
  def update
    integration = Integration.for_project(current_project).find(params[:id])

    # Azure has its own editable settings (the operation profile, and a
    # replacement PAT), so it routes away from the Coder path rather than being
    # refused by it.
    return update_azure_devops(integration) if integration.azure_devops?

    Coder::IntegrationService.new(
      company: current_company,
      connected_by: current_user,
      project: current_project
    ).update_settings(
      integration:      integration,
      default_template: params[:default_template],
      machine_prefix:   params[:machine_prefix],
      lock_ttl_minutes: params[:lock_ttl_minutes]
    )

    redirect_to company_project_integrations_path(current_project), notice: "Integration settings saved"
  rescue Coder::IntegrationService::ConfigurationError => e
    redirect_to company_project_integrations_path(current_project), alert: e.message
  end

  def destroy
    integration = Integration.for_project(current_project).find(params[:id])
    integration.destroy
    redirect_to company_project_integrations_path(current_project), notice: "Integration removed"
  end

  # Re-verify a connection without mutating anything in Azure. Used by the
  # card's "Test connection" and "Repair connection" buttons, which are the same
  # operation: repair keeps the integration id and its repository attachments.
  def test_connection
    integration = Integration.for_project(current_project).find(params[:id])
    unless integration.azure_devops?
      return redirect_to company_project_integrations_path(current_project),
                         alert: "This integration has no connection test"
    end

    result = AzureDevops::IntegrationService.new(
      company: current_company, connected_by: current_user, project: current_project
    ).test(integration)

    if result[:status] == :active
      redirect_to company_project_integrations_path(current_project), notice: "Connection verified"
    else
      redirect_to company_project_integrations_path(current_project),
                  alert: "Connection failed: #{result[:message]}"
    end
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

  private

  # What the page needs to offer Azure DevOps at all: whether the deployment
  # enables it, which approved organization installations this company holds,
  # and which Azure projects each one may expose. An arbitrary organization URL
  # is never enough — the binding has to exist first.
  def azure_devops_props
    return { enabled: false } unless AzureDevops::AppConfig.enabled?

    installations = AzureDevopsInstallation.for_company(current_company).active.order(:organization_slug)
    {
      enabled: true,
      pat_mode_enabled: AzureDevops::AppConfig.pat_mode_enabled?,
      installations: installations.map do |installation|
        {
          id: installation.id,
          organization_slug: installation.organization_slug,
          tenant_id: installation.tenant_id,
          status: installation.status.to_s,
          last_verified_at: installation.last_verified_at,
          # Approved scope only. Azure's own answer is intersected with this in
          # the service; showing everything Azure returns would advertise
          # projects nobody signed off on.
          projects: azure_projects_for(installation)
        }
      end
    }
  end

  # Best effort: a listing failure must not take the whole integrations page
  # down, and the card can explain a connection problem on its own.
  def azure_projects_for(installation)
    AzureDevops::InstallationService.new(company: current_company).approved_projects(installation)
  rescue AzureDevops::Error => e
    Rails.logger.warn("[Integrations] Azure project listing failed for installation #{installation.id}: #{e.code}")
    []
  end

  def create_azure_devops
    service = AzureDevops::IntegrationService.new(
      company: current_company, connected_by: current_user, project: current_project
    )

    integration =
      if params[:auth_mode].to_s == "pat"
        service.create_with_pat(
          organization_slug: params[:organization_slug].to_s,
          azure_project_id: params[:azure_project_id].to_s,
          personal_access_token: params[:personal_access_token].to_s,
          enabled_capabilities: params[:enabled_capabilities]
        )
      else
        service.create_with_installation(
          installation_id: params[:azure_devops_installation_id],
          azure_project_id: params[:azure_project_id].to_s,
          enabled_capabilities: params[:enabled_capabilities]
        )
      end

    redirect_to company_project_integrations_path(current_project),
                notice: "Azure DevOps connected as #{integration.name}"
  rescue AzureDevops::IntegrationService::ConfigurationError => e
    redirect_to company_project_integrations_path(current_project), alert: e.message
  end

  # Editable on an Azure connection: the operation profile, and a replacement
  # PAT. The organization and the selected Azure project are deliberately not
  # editable — changing either would silently re-point existing repository and
  # work-item references at a different target, so that is a new connection.
  def update_azure_devops(integration)
    service = AzureDevops::IntegrationService.new(
      company: current_company, connected_by: current_user, project: current_project
    )

    if params[:personal_access_token].present?
      service.replace_pat(integration, personal_access_token: params[:personal_access_token].to_s)
    end

    if params[:enabled_capabilities].present?
      allowed = Array(params[:enabled_capabilities]).map(&:to_s) &
                AzureDevops::IntegrationService::DEFAULT_CAPABILITIES
      integration.settings = integration.settings.to_h.merge("enabled_capabilities" => allowed)
      integration.save!
    end

    redirect_to company_project_integrations_path(current_project), notice: "Integration settings saved"
  rescue AzureDevops::IntegrationService::ConfigurationError, AzureDevops::Error => e
    redirect_to company_project_integrations_path(current_project), alert: e.message
  end
end
