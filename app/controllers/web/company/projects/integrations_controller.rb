# frozen_string_literal: true

class Web::Company::Projects::IntegrationsController < Web::Company::Projects::ApplicationController
  def index
    integrations = Integration.visible_for_project(current_project)
                              .includes(:connected_by, :azure_devops_installation, :tracker_subscriptions)
                              .order(created_at: :desc)

    render inertia: "Projects/Integrations/IntegrationsPage", props: {
      project: project_props,
      integrations: integrations.map { |i| IntegrationResource.new(i).to_h },
      azure_devops: azure_devops_props,
      github: github_props,
      jira: { oauth_enabled: Jira::AppConfig.oauth_enabled? },
      linear: { oauth_enabled: Linear::AppConfig.oauth_enabled? },
      youtrack: { enabled: true },
      slack: { enabled: Slack::Oauth.enabled? }
    }
  end

  # Slack connects via OAuth (see #slack_oauth_start + Web::Integrations::SlackOauthController),
  # not this paste-credentials path.
  def create
    case params[:provider].to_s
    when "github" then create_github
    when "gitlab" then create_gitlab
    when "coder" then create_coder
    when "azure_devops" then create_azure_devops
    when "jira" then create_jira
    when "linear" then create_linear
    when "youtrack" then create_youtrack
    else
      redirect_to company_project_integrations_path(current_project), alert: "Unsupported provider: #{params[:provider]}"
    end
  end

  # Edits provider settings on an already-connected integration. Scoped with
  # `for_project` like #destroy: a company-wide integration is shared by every
  # project, so it is not editable from one project's page.
  def update
    integration = Integration.for_project(current_project).find(params[:id])

    # Each provider has its own editable part: Azure its operation profile and
    # a replacement PAT, Jira its projects, GitLab its token, Coder its token
    # or its pool settings.
    return update_azure_devops(integration) if integration.azure_devops?
    return update_jira(integration) if integration.jira?
    return update_linear(integration) if integration.linear?
    return update_youtrack(integration) if integration.youtrack?
    return update_github_projects(integration) if integration.github? && params.key?(:github_project_ids)
    return replace_gitlab_token(integration) if integration.gitlab?
    return replace_coder_token(integration) if params.key?(:session_token)

    coder_service.update_settings(
      integration:      integration,
      default_template: params[:default_template],
      machine_prefix:   params[:machine_prefix],
      lock_ttl_minutes: params[:lock_ttl_minutes]
    )

    redirect_to company_project_integrations_path(current_project), notice: "Integration settings saved"
  rescue Coder::IntegrationService::ConfigurationError => e
    redirect_to company_project_integrations_path(current_project), alert: e.message
  end

  # A company-wide install (Slack) serves every project and has no page of its
  # own, so a company admin removes it from any of them.
  def destroy
    integration = Integration.visible_for_project(current_project).find(params[:id])
    if integration.project_id.nil? && !current_project_membership&.admin?
      return redirect_to company_project_integrations_path(current_project),
                         alert: "Only a company admin can remove a company-wide integration"
    end

    integration.destroy
    redirect_to company_project_integrations_path(current_project), notice: "Integration removed"
  end

  # Re-verify a connection without changing anything at the provider. Used by the
  # card's "Test connection" and "Repair connection" buttons, which are the same
  # operation: repair keeps the integration id and its repository attachments.
  def test_connection
    integration = Integration.for_project(current_project).find(params[:id])
    service_class = {
      "azure_devops" => AzureDevops::IntegrationService, "jira" => Jira::IntegrationService,
      "linear" => Linear::IntegrationService, "youtrack" => Youtrack::IntegrationService,
      "github" => Github::IntegrationService, "gitlab" => Gitlab::IntegrationService,
      "coder" => Coder::IntegrationService
    }[integration.provider.to_s]
    unless service_class
      return redirect_to company_project_integrations_path(current_project),
                         alert: "This integration has no connection test"
    end

    result = service_class.new(company: current_company, connected_by: current_user, project: current_project)
                          .test(integration)

    if result[:status] == :active
      redirect_to company_project_integrations_path(current_project),
                  (result[:warning] ? :alert : :notice) => result[:message] || "Connection verified"
    else
      redirect_to company_project_integrations_path(current_project),
                  alert: "Connection failed: #{result[:message]}"
    end
  end

  # Azure DevOps through "Sign in with Microsoft": an organization
  # administrator consents to Aixle's application at Microsoft, and comes back
  # to the connect dialog (Web::Integrations::AzureDevopsOauthController).
  def azure_devops_sign_in
    # allow_other_host: login.microsoftonline.com, built from deployment Settings.
    redirect_to AzureDevops::AdminSignIn.authorize_url(project: current_project, user: current_user,
                                                       organization: params[:organization].to_s),
                allow_other_host: true
  rescue AzureDevops::Error => e
    redirect_to company_project_integrations_path(current_project), alert: e.message
  end

  # Step one of Azure DevOps self-service onboarding: prove the caller
  # administers the organization, and show what it holds.
  #
  # The proof is a Microsoft sign-in (held server-side under `sign_in`) or a
  # personal access token, used inside this request and nowhere else — not
  # persisted, not logged, and not what the connection later runs on. It is
  # the proof that this company may bind this organization at all, which is the
  # one thing our application's own access cannot establish: with a
  # multi-tenant application the answer to "can we reach that organization" is
  # legitimately yes for every customer that installed us.
  def azure_devops_inspect
    result = azure_onboarding.inspect!(
      organization: params[:organization].to_s, admin: azure_admin_credential
    )

    render json: {
      organization: result.organization,
      tenantId: result.tenant_id,
      identity: result.identity,
      alreadyBound: result.already_bound,
      projects: result.projects.map { |p| { id: p[:id], name: p[:name] } }
    }
  rescue AzureDevops::Error => e
    render json: { error: e.code, message: e.message }, status: :unprocessable_content
  end

  # Step two: entitle the application in the organization and record the
  # binding. Idempotent — reconnecting an organization already bound widens its
  # approved project list rather than duplicating it.
  def azure_devops_connect
    installation = azure_onboarding.complete!(
      organization: params[:organization].to_s, admin: azure_admin_credential, project_ids: params[:project_ids]
    )
    AzureDevops::AdminSignIn.release(params[:sign_in])

    render json: { installationId: installation.id, organization: installation.organization_slug,
                   projects: installation.allowed_project_ids }
  rescue AzureDevops::Error => e
    render json: { error: e.code, message: e.message }, status: :unprocessable_content
  end

  # Kick off the Slack OAuth install for this project: redirect to Slack's consent
  # screen with a signed `state` that carries the project. Slack redirects back to
  # the deployment-wide callback (Web::Integrations::SlackOauthController#callback).
  def slack_oauth_start
    unless Slack::Oauth.enabled?
      return redirect_to company_project_integrations_path(current_project), alert: "Slack's app is not configured"
    end

    # allow_other_host: the target is Slack's hardcoded authorize URL built from
    # deployment Settings.slack.* — never user-supplied.
    redirect_to Slack::Oauth.authorize_url(project: current_project, user: current_user), allow_other_host: true
  end

  # Jira through Aixle's Atlassian OAuth app. A plain link, like Slack's: the
  # browser has to leave for Atlassian's consent screen.
  def jira_oauth_start
    unless Jira::AppConfig.oauth_enabled?
      return redirect_to company_project_integrations_path(current_project), alert: "Jira's OAuth app is not configured"
    end

    # allow_other_host: auth.atlassian.com, built from deployment Settings.
    redirect_to Jira::Oauth.authorize_url(project: current_project, user: current_user), allow_other_host: true
  end

  # What a service account's credential reaches on a site, before anything is
  # saved: the dialog shows the projects to pick from.
  def jira_inspect
    inspection = jira_service.inspect_service_account(
      site_url: params[:site_url].to_s, client_id: params[:client_id].to_s, client_secret: params[:client_secret].to_s
    )
    render json: { site: inspection.site, identity: inspection.identity.slice(:id, :name), projects: inspection.projects }
  rescue Jira::Error, Jira::IntegrationService::ConfigurationError => e
    render json: { error: e.try(:code) || "validation_failed", message: e.message }, status: :unprocessable_content
  end

  # The projects a Jira connection can see — the picker that finishes a 3LO
  # connection, or changes one.
  def jira_projects
    integration = Integration.for_project(current_project).where(provider: :jira).find(params[:id])
    render json: { projects: jira_service.available_projects(integration, cloud_id: params[:cloud_id].presence) }
  rescue Jira::Error, Jira::IntegrationService::ConfigurationError => e
    render json: { error: e.try(:code) || "validation_failed", message: e.message }, status: :unprocessable_content
  end

  # What a Jira admin enters as a system webhook for a service-account
  # connection. The secret is shown to the people who manage integrations and
  # never goes into settings, which every viewer of the page receives.
  def jira_webhook
    integration = Integration.for_project(current_project).where(provider: :jira).find(params[:id])
    return head :not_found unless integration.settings.to_h["auth_mode"] == "service_account"

    subscription = Trackers::Jira::Subscriptions.new(integration).ensure!
    keys = Array(integration.settings.to_h["jira_projects"]).pluck("key").compact
    render json: {
      url: subscription.callback_url(Jira::AppConfig.webhook_base_url), secret: subscription.secret,
      events: [ "Issue: created", "Issue: updated", "Comment: created" ],
      jql: keys.any? ? "project IN (#{keys.join(', ')})" : nil, lastEventAt: subscription.last_event_at
    }
  end

  # Linear through Aixle's OAuth app, which a workspace admin installs.
  def linear_oauth_start
    unless Linear::AppConfig.oauth_enabled?
      return redirect_to company_project_integrations_path(current_project), alert: "Linear's OAuth app is not configured"
    end

    # allow_other_host: linear.app, built from deployment Settings.
    redirect_to Linear::Oauth.authorize_url(project: current_project, user: current_user), allow_other_host: true
  end

  # Who an API key acts as and the teams it can see, before anything is saved.
  def linear_inspect
    inspection = linear_service.inspect_api_key(api_key: params[:api_key].to_s)
    identity = inspection.identity
    render json: { identity: { id: identity[:id], name: identity[:name] }, organization: identity[:organization],
                   teams: inspection.teams }
  rescue Trackers::Error, Linear::IntegrationService::ConfigurationError => e
    render json: { error: e.try(:code) || "validation_failed", message: e.message }, status: :unprocessable_content
  end

  # The teams a Linear connection can see — the picker that finishes an OAuth
  # connection, or changes one.
  def linear_teams
    integration = Integration.for_project(current_project).where(provider: :linear).find(params[:id])
    render json: { teams: linear_service.available_teams(integration) }
  rescue Trackers::Error, Linear::IntegrationService::ConfigurationError => e
    render json: { error: e.try(:code) || "validation_failed", message: e.message }, status: :unprocessable_content
  end

  # Who a permanent token acts as and the projects it can see, before anything is saved.
  def youtrack_inspect
    inspection = youtrack_service.inspect_token(base_url: params[:base_url].to_s, token: params[:permanent_token].to_s)
    render json: { base_url: inspection.base_url, identity: inspection.identity.slice(:id, :login, :name),
                   projects: inspection.projects }
  rescue Trackers::Error, Youtrack::IntegrationService::ConfigurationError => e
    render json: { error: e.try(:code) || "validation_failed", message: e.message }, status: :unprocessable_content
  end

  def youtrack_projects
    integration = Integration.for_project(current_project).where(provider: :youtrack).find(params[:id])
    render json: { projects: youtrack_service.available_projects(integration) }
  rescue Trackers::Error, Youtrack::IntegrationService::ConfigurationError => e
    render json: { error: e.try(:code) || "validation_failed", message: e.message }, status: :unprocessable_content
  end

  # What a YouTrack project admin enters in each project's Webhook Triggers
  # app. The tokens are shown to the people who manage integrations and never
  # go into settings, which every viewer of the page receives.
  def youtrack_webhook
    integration = Integration.for_project(current_project).where(provider: :youtrack).find(params[:id])
    subscriptions = Trackers::Youtrack::Subscriptions.new(integration).ensure!
    render json: { projects: subscriptions.map { |subscription| youtrack_webhook_json(integration, subscription) },
                   events: Trackers::Youtrack::Webhooks::EVENTS }
  end

  # The token a YouTrack project's Webhook Triggers app already sends, when
  # it serves other consumers too and keeps it.
  def youtrack_webhook_token
    integration = Integration.for_project(current_project).where(provider: :youtrack).find(params[:id])
    subscription = Trackers::Youtrack::Subscriptions.new(integration)
                                                   .use_token!(params[:scope_id].to_s, token: params[:token], header: params[:header])
    render json: youtrack_webhook_json(integration, subscription)
  rescue Trackers::Error => e
    render json: { error: e.code, message: e.message }, status: :unprocessable_content
  end

  # The organization projects a GitHub App connection can put on the Trackers
  # page, and the ones it already covers.
  def github_projects
    integration = Integration.for_project(current_project).where(provider: :github).find(params[:id])
    render json: { projects: github_service.available_projects(integration),
                   selected: Array(integration.settings.to_h["github_projects"]).pluck("id") }
  rescue Trackers::Error, Github::IntegrationService::ConfigurationError => e
    render json: { error: e.try(:code) || "validation_failed", message: e.message }, status: :unprocessable_content
  end

  # Kick off a GitHub App installation for this project. The GitHub App "Setup URL"
  # is app-wide, so we carry the originating project in a SIGNED `state` (Oauth::State:
  # signed + 10-min TTL + single-use nonce + user pinning) instead of the old
  # plaintext `project:<id>` (replayable, forgeable — oauth-unification §7). GitHub
  # echoes `state` back to the deployment-wide callback (GithubSetupController).
  def github_app_install
    unless Github::TokenService.app_configured?
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
    redirect_to "https://github.com/apps/#{Settings.github.app_slug}/installations/new?state=#{CGI.escape(state)}",
                allow_other_host: true
  end

  private

  # GitHub connects two ways. The App path arrives on GitHub's post-install
  # redirect (GithubSetupController); the PAT path posts a token pasted into the
  # dialog. Which credential is read is decided by the declared mode, never by
  # which parameter happens to be present — switching mode in the dialog must
  # not be able to submit the other path's credential.
  #
  # A rejected token answers with an Inertia validation error rather than a
  # flash alert, so the dialog can keep itself open and show why against the
  # field: a redirect-with-alert would close it and lose what was typed.
  def create_github
    service = Github::IntegrationService.new(
      company: current_company, connected_by: current_user, project: current_project
    )

    if params[:auth_mode].to_s == "pat"
      integration = service.create_with_pat(personal_access_token: params[:personal_access_token].to_s)

      if integration.persisted? && integration.active?
        return redirect_to company_project_integrations_path(current_project),
                           notice: "GitHub connected as #{integration.name}"
      end

      return redirect_to company_project_integrations_path(current_project),
                         inertia: { errors: {
                           personal_access_token: integration.settings&.dig("error") || "Failed to connect GitHub"
                         } }
    end

    redirect_to company_project_integrations_path(current_project),
                alert: "The GitHub App connects through its install on GitHub — choose Connect → GitHub"
  end

  # Whether the GitHub App path can be walked on this deployment at all.
  #
  # The dialog offers both modes regardless — the point of PAT mode is that it
  # works where no App exists — but an App button that can only ever redirect to
  # "GitHub App is not configured" is worse than one that says so up front, and
  # on such a deployment the dialog opens on the path that works.
  def github_props
    { app_configured: Github::TokenService.app_configured? }
  end

  # Whether the page may offer Azure DevOps at all, and nothing else.
  #
  # It deliberately does NOT list the organizations this company is bound to.
  # Enumerating them told every project member which Azure organizations the
  # company works with, and it bought nothing: the user types the organization
  # they mean, and the server resolves it against this company's own bindings.
  # What is not listed cannot be browsed.
  # `client_id` is deliberately included. It is not a secret — Microsoft
  # publishes it in every authorization URL — and it is the one value a customer
  # needs before they can connect at all: `az ad sp create --id <it>` in their
  # own Entra directory. Documentation cannot carry it, because it differs
  # between the hosted deployment and every self-hosted one; the dialog knows
  # which deployment this is.
  def azure_devops_props
    return { enabled: false } unless AzureDevops::AppConfig.enabled?

    { enabled: true,
      pat_mode_enabled: AzureDevops::AppConfig.pat_mode_enabled?,
      client_id: AzureDevops::AppConfig.fetch("default")&.client_id }
  end

  # Array of strings, whatever shape the parameter arrives in. An
  # ActionController::Parameters hash responds to neither to_ary nor to_a, so
  # `Array()` would wrap it whole and stringify it into junk.
  def capability_params
    raw = params[:enabled_capabilities]
    case raw
    when ActionController::Parameters then raw.values.map(&:to_s)
    when Array then raw.map(&:to_s)
    when nil then []
    else [ raw.to_s ]
    end
  end

  # A refused token answers with an Inertia validation error, like GitHub's
  # token path, so the dialog stays open and says why.
  def create_gitlab
    integration = gitlab_service.create(personal_access_token: params[:personal_access_token].to_s)
    redirect_to company_project_integrations_path(current_project), notice: "GitLab connected as #{integration.name}"
  rescue Gitlab::IntegrationService::ConnectionError => e
    redirect_to company_project_integrations_path(current_project),
                inertia: { errors: { personal_access_token: e.message } }
  end

  def replace_gitlab_token(integration)
    integration = gitlab_service.replace_token(integration, personal_access_token: params[:personal_access_token].to_s)
    redirect_to company_project_integrations_path(current_project), notice: "Token replaced on #{integration.name}"
  rescue Gitlab::IntegrationService::ConnectionError => e
    redirect_to company_project_integrations_path(current_project),
                inertia: { errors: { personal_access_token: e.message } }
  end

  def create_coder
    integration = coder_service.create(
      coder_url:        params[:coder_url].to_s,
      session_token:    params[:session_token].to_s,
      default_template: params[:default_template].presence,
      machine_prefix:   params[:machine_prefix].presence,
      lock_ttl_minutes: params[:lock_ttl_minutes].presence
    )
    redirect_to company_project_integrations_path(current_project), notice: "#{integration.name} connected"
  rescue Coder::IntegrationService::ConnectionError => e
    redirect_to company_project_integrations_path(current_project), inertia: { errors: { coder: e.message } }
  end

  def replace_coder_token(integration)
    integration = coder_service.replace_token(integration, session_token: params[:session_token].to_s)
    redirect_to company_project_integrations_path(current_project), notice: "Token replaced on #{integration.name}"
  rescue Coder::IntegrationService::ConnectionError => e
    redirect_to company_project_integrations_path(current_project), inertia: { errors: { session_token: e.message } }
  end

  def gitlab_service
    Gitlab::IntegrationService.new(company: current_company, connected_by: current_user, project: current_project)
  end

  def coder_service
    Coder::IntegrationService.new(company: current_company, connected_by: current_user, project: current_project)
  end

  def github_service
    Github::IntegrationService.new(company: current_company, connected_by: current_user, project: current_project)
  end

  def update_github_projects(integration)
    github_service.configure_projects(integration, project_ids: Array(params[:github_project_ids]))
    redirect_to company_project_integrations_path(current_project), notice: "GitHub projects saved"
  rescue Trackers::Error, Github::IntegrationService::ConfigurationError => e
    redirect_to company_project_integrations_path(current_project), alert: "GitHub Projects: #{e.message}"
  end

  def linear_service
    Linear::IntegrationService.new(company: current_company, connected_by: current_user, project: current_project)
  end

  def create_linear
    integration = linear_service.connect_api_key(
      api_key: params[:api_key].to_s, team_ids: Array(params[:team_ids]), dedicated_identity: params[:dedicated_identity]
    )
    redirect_to company_project_integrations_path(current_project), notice: "#{integration.name} connected"
  rescue Trackers::Error, Linear::IntegrationService::ConfigurationError => e
    redirect_to company_project_integrations_path(current_project), alert: "Linear connection failed: #{e.message}"
  end

  # The teams, and for an API key whether its account is kept for Aixle. The
  # key itself is replaced by connecting again, which verifies it.
  def update_linear(integration)
    integration = linear_service.configure(
      integration, team_ids: Array(params[:team_ids]),
                   dedicated_identity: params.key?(:dedicated_identity) ? params[:dedicated_identity] : nil
    )
    redirect_to company_project_integrations_path(current_project), notice: "#{integration.name} saved"
  rescue Trackers::Error, Linear::IntegrationService::ConfigurationError => e
    redirect_to company_project_integrations_path(current_project), alert: "Linear: #{e.message}"
  end

  def youtrack_service
    @youtrack_service ||= Youtrack::IntegrationService.new(company: current_company, connected_by: current_user,
                                                           project: current_project)
  end

  def create_youtrack
    integration = youtrack_service.connect(
      base_url: params[:base_url].to_s, token: params[:permanent_token].to_s, project_ids: Array(params[:project_ids]),
      dedicated_identity: params[:dedicated_identity]
    )
    previous = youtrack_service.previous_login
    notice = "#{integration.name} connected#{" — it now acts as @#{integration.settings['identity_login']}, not @#{previous}" if previous}"
    redirect_to company_project_integrations_path(current_project), (previous ? :alert : :notice) => notice
  rescue Trackers::Error, Youtrack::IntegrationService::ConfigurationError => e
    redirect_to company_project_integrations_path(current_project), alert: "YouTrack connection failed: #{e.message}"
  end

  # The projects, and whether the token's account is kept for Aixle. The token
  # itself is replaced by connecting again, which verifies it.
  def update_youtrack(integration)
    integration = youtrack_service.configure(
      integration, project_ids: Array(params[:project_ids]),
                   dedicated_identity: params.key?(:dedicated_identity) ? params[:dedicated_identity] : nil
    )
    redirect_to company_project_integrations_path(current_project), notice: "#{integration.name} saved"
  rescue Trackers::Error, Youtrack::IntegrationService::ConfigurationError => e
    redirect_to company_project_integrations_path(current_project), alert: "YouTrack: #{e.message}"
  end

  def youtrack_webhook_json(integration, subscription)
    project = Array(integration.settings.to_h["youtrack_projects"]).find { |p| p["id"].to_s == subscription.external_scope_id }
    {
      scopeId: subscription.external_scope_id, key: project&.dig("key"), name: project&.dig("name"),
      url: Trackers::Youtrack::Webhooks.url(subscription), header: Trackers::Youtrack::Webhooks.header(subscription),
      token: subscription.secret, status: subscription.status, lastEventAt: subscription.last_event_at
    }
  end

  def jira_service
    Jira::IntegrationService.new(company: current_company, connected_by: current_user, project: current_project)
  end

  def create_jira
    integration = jira_service.connect_service_account(
      site_url: params[:site_url].to_s, client_id: params[:client_id].to_s, client_secret: params[:client_secret].to_s,
      project_ids: jira_project_id_params
    )
    redirect_to company_project_integrations_path(current_project), notice: "#{integration.name} connected"
  rescue Jira::Error, Jira::IntegrationService::ConfigurationError => e
    redirect_to company_project_integrations_path(current_project), alert: "Jira connection failed: #{e.message}"
  end

  # The site (a 3LO grant's pick) and the projects. The credential itself is
  # replaced by reconnecting, which verifies it.
  def update_jira(integration)
    integration = jira_service.configure(
      integration, project_ids: jira_project_id_params, cloud_id: params[:cloud_id].presence,
                   dedicated_identity: params.key?(:dedicated_identity) ? params[:dedicated_identity] : nil
    )
    redirect_to company_project_integrations_path(current_project), notice: "#{integration.name} saved"
  rescue Jira::Error, Jira::IntegrationService::ConfigurationError => e
    redirect_to company_project_integrations_path(current_project), alert: "Jira: #{e.message}"
  end

  def jira_project_id_params
    Array(params[:project_ids]).map(&:to_s).compact_blank.uniq
  end

  def azure_admin_credential
    return AzureDevops::AdminCredential.pat(params[:personal_access_token]) if params[:sign_in].blank?

    AzureDevops::AdminSignIn.fetch(params[:sign_in], user: current_user, organization: params[:organization]) ||
      raise(AzureDevops::NotAuthorized, "Your Microsoft sign-in has expired. Sign in again to continue.")
  end

  def azure_onboarding
    AzureDevops::Onboarding.new(company: current_company, actor: current_user)
  end

  def create_azure_devops
    service = AzureDevops::IntegrationService.new(
      company: current_company, connected_by: current_user, project: current_project
    )

    integration =
      if params[:auth_mode].to_s == "pat"
        service.create_with_pat(
          organization_slug: params[:organization_slug].to_s,
          azure_project_ids: azure_project_id_params,
          azure_project_names: azure_project_name_params,
          personal_access_token: params[:personal_access_token].to_s,
          enabled_capabilities: params.key?(:enabled_capabilities) ? capability_params : nil
        )
      else
        service.create_with_installation(
          installation_id: params[:azure_devops_installation_id],
          azure_project_ids: azure_project_id_params,
          azure_project_names: azure_project_name_params,
          enabled_capabilities: params.key?(:enabled_capabilities) ? capability_params : nil
        )
      end

    redirect_to company_project_integrations_path(current_project),
                notice: "Azure DevOps connected as #{integration.name}"
  rescue AzureDevops::IntegrationService::ConfigurationError => e
    redirect_to company_project_integrations_path(current_project), alert: e.message
  end

  # Accepts the list, and the single value connections were created with before
  # it — a browser tab left open across the deploy still posts the old shape.
  def azure_project_id_params
    ids = params[:azure_project_ids].presence || params[:azure_project_id]
    Array(ids).map(&:to_s).reject(&:blank?).uniq
  end

  # Display names only; IntegrationService intersects them with the ids it
  # actually approved, so nothing here reaches settings unchecked.
  def azure_project_name_params
    names = params[:azure_project_names]
    return {} unless names.respond_to?(:to_unsafe_h) || names.is_a?(Hash)

    (names.respond_to?(:to_unsafe_h) ? names.to_unsafe_h : names).to_h
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

    # `key?`, not `present?`: unticking every box submits an empty list, and
    # treating that as "said nothing" silently kept the old set — the one edit a
    # user makes to revoke everything was the one that did not work.
    if params.key?(:enabled_capabilities)
      integration.settings = integration.settings.to_h.merge(
        "enabled_capabilities" => AzureDevops::IntegrationService.sanitize_capabilities(
          capability_params
        )
      )
      integration.save!
    end

    redirect_to company_project_integrations_path(current_project), notice: "Integration settings saved"
  rescue AzureDevops::IntegrationService::ConfigurationError, AzureDevops::Error => e
    redirect_to company_project_integrations_path(current_project), alert: e.message
  end
end
