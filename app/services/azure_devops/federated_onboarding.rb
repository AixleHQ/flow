# frozen_string_literal: true

module AzureDevops
  # Connecting an Azure DevOps organization through the customer's OWN Entra app,
  # which trusts this deployment as an OIDC issuer (workload identity federation).
  #
  # There is no administrator credential anywhere in this flow, which is the point.
  # What the shared-app onboarding proves with an admin token is proven here by
  # the token exchange itself: it succeeds only if someone who controls an app in
  # that organization's directory created a federated credential naming exactly
  # this company's subject. Company B cannot reuse company A's app, because B's
  # assertion carries B's subject. The access is then whatever the customer's
  # administrator granted that app in Azure DevOps — they add it to the
  # organization once, in their own portal (see SetupScript).
  #
  # Two phases, as in Onboarding: `inspect!` changes nothing and shows what the app
  # reaches; `complete!` records the binding.
  class FederatedOnboarding
    Inspection = Struct.new(:organization, :tenant_id, :projects, :permissions, :already_bound,
                            keyword_init: true)

    # Holds a token already obtained so a client can use it without an
    # installation row to cache it on.
    FixedToken = Struct.new(:token) do
      def access_token = token
      def refresh_after_unauthorized! = token
    end

    def initialize(company:, actor:, logger: Rails.logger)
      @company = company
      @actor = actor
      @logger = logger
    end

    attr_reader :company, :actor

    def self.available? = FederationConfig.enabled?

    # Nothing is written. Exchanges a token, lists the projects the app was
    # granted, and reports what it may do in each.
    def inspect!(organization:, client_id:, project_ids: nil)
      ensure_available!
      tenant = TenantDiscovery.call(organization)
      token = exchange(tenant, client_id)
      client = static_client(tenant.organization, token)

      projects = visible_projects(client)

      Inspection.new(
        organization: tenant.organization, tenant_id: tenant.tenant_id, projects: projects,
        permissions: permissions_for(client, projects, project_ids),
        already_bound: existing_installation(tenant)&.federated? || false
      )
    end

    # Records the binding. Idempotent: reconnecting widens the approved projects,
    # and connecting with a different client id (the customer recreated the app)
    # moves the installation to the new app once that app has been verified. All
    # of it happens in one transaction, so a failed exchange leaves nothing behind.
    def complete!(organization:, client_id:, project_ids:)
      ensure_available!
      project_ids = Array(project_ids).map(&:to_s).uniq
      raise ValidationFailed, "Choose at least one Azure project" if project_ids.empty?

      tenant = TenantDiscovery.call(organization)

      AzureDevopsInstallation.transaction do
        installation, rebound = bind(tenant, client_id.to_s.strip.downcase)
        token = AppTokenService.new(installation).access_token(force: true)
        client = Client.new(credential: credential_for(installation), organization: installation.organization_slug)

        visible = visible_projects(client)
        verify_projects!(project_ids, visible)
        report = PermissionCheck.new(client: client).call(visible.select { |p| project_ids.include?(p[:id]) })
        raise_if_blocked!(report)

        # Assigned only now: every request above goes through a token service that
        # reloads the row, which would discard an earlier assignment.
        installation.assign_attributes(
          allowed_project_ids: allowed_projects(installation, project_ids, visible, rebound),
          service_principal_object_id: TokenClaims.object_id!(token.value),
          status: :active, error_code: nil, last_verified_at: Time.current
        )
        installation.save!
        installation
      end
    end

    private

    def ensure_available!
      return if FederationConfig.enabled?

      raise IntegrationUnavailable, "Connecting with your own Entra app is not available on this deployment"
    end

    def exchange(tenant, client_id)
      payload = FederatedTokenExchange.call(tenant_id: tenant.tenant_id, client_id: client_id.to_s.strip.downcase,
                                            company: company)
      AppTokenService::Token.new(value: payload.fetch("access_token"),
                                 expires_at: Time.current + payload.fetch("expires_in", 3600).to_i.seconds)
    end

    def static_client(organization, token)
      credential = CredentialProvider::Resolved.new(
        integration: nil, installation: nil, mode: :service_principal, organization: organization,
        project_id: nil, token_service: FixedToken.new(token)
      )
      Client.new(credential: credential, organization: organization)
    end

    def credential_for(installation)
      CredentialProvider::Resolved.new(
        integration: nil, installation: installation, mode: :service_principal,
        organization: installation.organization_slug, project_id: nil,
        token_service: AppTokenService.new(installation)
      )
    end

    def existing_installation(tenant)
      AzureDevopsInstallation.find_by(company_id: company.id, tenant_id: tenant.tenant_id,
                                      organization_slug: tenant.organization)
    end

    # The installation row for this company and organization, saved INACTIVE so the
    # token service can cache on it. A new client id forgets what was learned about
    # the old app; its cached token is already unusable, because the cache is keyed
    # by client id. Returns the row and whether it moved to a different app.
    def bind(tenant, client_id)
      installation = existing_installation(tenant) ||
                     AzureDevopsInstallation.new(company: company, tenant_id: tenant.tenant_id,
                                                 organization_slug: tenant.organization)
      if installation.persisted? && !installation.federated?
        raise ValidationFailed,
              "'#{tenant.organization}' is already connected through Aixle's Microsoft app. " \
              "Disconnect it first to connect with your own app."
      end

      rebound = installation.persisted? && installation.client_id != client_id
      installation.service_principal_object_id = nil if rebound

      installation.assign_attributes(credential_kind: :federated, app_config_key: nil, client_id: client_id,
                                     status: :inactive, approved_by: actor)
      installation.approved_at ||= Time.current
      installation.save!
      [ installation, rebound ]
    end

    # Several requests per project, so only for the projects the caller names, not
    # for everything the app can see.
    def permissions_for(client, projects, project_ids)
      return nil if project_ids.blank?

      chosen = Array(project_ids).map(&:to_s)
      PermissionCheck.new(client: client).call(projects.select { |p| chosen.include?(p[:id]) })
    end

    def visible_projects(client)
      projects, = client.paginate("_apis", "projects", family: :core, limit: 200, params: { "$top" => 100 })
      projects.map { |p| { id: p["id"].to_s, name: p["name"].to_s } }
    end

    # Chosen projects must be among those the app can see. A project it cannot see
    # has not been granted to it yet, and a binding to it would fail on first use.
    def verify_projects!(project_ids, visible)
      missing = project_ids - visible.pluck(:id)
      return if missing.empty?

      raise Error.new(
        "The app cannot see #{missing.size} of the chosen projects. Add it to the organization and to those " \
        "projects in Azure DevOps (the setup script does this), then try again.",
        code: "project_not_granted"
      )
    end

    # Approval accumulates for the same app. When the customer moved to a new app,
    # only the projects that app can actually reach stay approved, plus the ones
    # chosen now.
    def allowed_projects(installation, chosen, visible, rebound)
      previous = installation.allowed_project_ids
      return previous | chosen unless rebound

      (previous & visible.pluck(:id)) | chosen
    end

    def raise_if_blocked!(report)
      return if report.ok?

      raise Error.new(
        "The app is missing permissions it needs. #{report.summary}. " \
        "Grant them in Azure DevOps (the setup script does this) and try again.",
        code: "permissions_missing", details: report.to_h.to_json
      )
    end
  end
end
