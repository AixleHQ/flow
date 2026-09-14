# frozen_string_literal: true

module AzureDevops
  # Self-service onboarding: a company binds itself to an Azure DevOps
  # organization, proving on the way that it is entitled to.
  #
  # This replaces an operator running a rake task. The operator was never adding
  # information — they were vouching, and a human vouching is both unauditable
  # and the one step that could quietly grant company A access to company B's
  # organization by typing the wrong id. Here the proof is technical: the
  # requester holds a token that can administer the organization, which is the
  # same authority that would have to add our application to it by hand.
  #
  # Two phases, because the user chooses in between:
  #
  #   inspect  → discover the tenant, prove the token administers the
  #              organization, and list the projects it can see
  #   complete → entitle the application in the organization, confirm it can
  #              actually read the chosen projects, and record the binding
  #
  # The personal access token lives for the length of one request. It is never
  # persisted, never logged, and is not what the connection later runs on — that
  # is the service principal.
  class Onboarding
    ENTITLEMENTS_HOST = "https://vsaex.dev.azure.com"
    ENTITLEMENTS_VERSION = "7.1-preview.1"

    # Azure's enum spells Basic as `express`. Anything less cannot read
    # repositories at all, and the resulting error names a missing repository
    # rather than a missing license.
    BASIC_LICENSE = "express"

    Inspection = Struct.new(:organization, :tenant_id, :identity, :projects, :already_bound,
                            keyword_init: true)

    def initialize(company:, actor:, logger: Rails.logger)
      @company = company
      @actor = actor
      @logger = logger
    end

    attr_reader :company, :actor

    # Phase one. Nothing is written and nothing in Azure is changed.
    #
    # A token is required only the FIRST time a company binds an organization.
    # After that the binding itself is the proof — it was established by someone
    # who demonstrated control, and asking a colleague to produce another
    # administrator token just to connect a second project would be theatre.
    def inspect!(organization:, personal_access_token: nil)
      tenant = TenantDiscovery.call(organization)
      bound = existing_installation(tenant)

      if bound&.active?
        # A token widens the approved set. Without one this branch could only
        # ever offer what the FIRST connection approved, so a company that later
        # wanted a second Azure project had no way to add it: `complete!` can
        # widen the installation, and nothing ever showed the wider list to
        # choose from.
        if personal_access_token.present?
          proof = OwnershipProof.new(organization: organization, personal_access_token: personal_access_token)
          verified = proof.call

          return Inspection.new(
            organization: tenant.organization, tenant_id: tenant.tenant_id,
            identity: verified.identity, already_bound: true,
            # Everything the administrator can see, not just the approved slice —
            # approving more is the point of having supplied a token.
            projects: proof.projects
          )
        end

        return Inspection.new(
          organization: tenant.organization, tenant_id: tenant.tenant_id,
          identity: nil, already_bound: true,
          # Listed with the APPLICATION's credential, and therefore only what it
          # can actually reach — no PAT involved on this path at all.
          projects: application_projects(bound)
        )
      end

      if personal_access_token.blank?
        raise ValidationFailed,
              "Connecting '#{tenant.organization}' for the first time needs a personal access token " \
              "from someone who can administer it."
      end

      proof = OwnershipProof.new(organization: organization, personal_access_token: personal_access_token)
      verified = proof.call

      Inspection.new(
        organization: tenant.organization, tenant_id: tenant.tenant_id,
        identity: verified.identity, projects: proof.projects, already_bound: false
      )
    end

    # Phase two. Everything here is idempotent: re-running it on an organization
    # already bound updates the approved project list rather than duplicating
    # anything.
    def complete!(organization:, personal_access_token: nil, project_ids:)
      project_ids = Array(project_ids).map(&:to_s).uniq
      raise ValidationFailed, "Choose at least one Azure project" if project_ids.empty?

      tenant = TenantDiscovery.call(organization)
      bound = existing_installation(tenant)

      # Already bound and the projects are already approved: nothing to prove and
      # nothing to change in Azure.
      if bound&.active? && (project_ids - bound.allowed_project_ids).empty?
        return bound
      end

      if personal_access_token.blank?
        raise ValidationFailed, "A personal access token is required to approve new projects for this organization"
      end

      OwnershipProof.call(organization: organization, personal_access_token: personal_access_token)

      installation = build_installation(tenant, project_ids)

      # The application's own object id IN THIS TENANT, which is what the
      # entitlement API takes. It arrives in the token Entra just issued —
      # the `oid` claim — so nobody has to find it in the portal and paste it.
      principal_object_id = service_principal_object_id(installation)

      entitle!(organization: organization, personal_access_token: personal_access_token,
               principal_object_id: principal_object_id, project_ids: project_ids)

      # Spend the token once more, on a permission rather than on a resource:
      # from here the application can create its own Service Hook subscriptions,
      # at connect time and on every later re-test. Creating them WITH this
      # token instead would tie every subscription to one person's continued
      # access — see ServiceHookGrant.
      #
      # Best effort. An organization that refuses it still gets a working
      # connection; its CI gates resolve through the recovery sweep instead of
      # through events, which is slower and not broken.
      grant_service_hook_permission(installation, principal_object_id,
                                    personal_access_token, project_ids)

      # Prove it worked using the APPLICATION's credential rather than the
      # user's token. Until this passes, the binding would be a promise about
      # access nobody has demonstrated.
      confirm_application_access!(installation, project_ids)

      installation.update!(service_principal_object_id: principal_object_id,
                           status: :active, error_code: nil, last_verified_at: Time.current)
      installation
    end

    private

    # What the application itself can see, for an organization already bound.
    # Intersected with the approved list, same as everywhere else: Azure's answer
    # alone would offer projects nobody signed off on.
    def application_projects(installation)
      InstallationService.new(company: company).approved_projects(installation)
    rescue Error => e
      @logger.warn("[AzureDevops::Onboarding] listing projects for installation " \
                   "#{installation.id} failed: #{e.code}")
      []
    end

    def existing_installation(tenant)
      AzureDevopsInstallation.find_by(company_id: company.id, tenant_id: tenant.tenant_id,
                                      organization_slug: tenant.organization)
    end

    def build_installation(tenant, project_ids)
      app = AppConfig.fetch("default")
      app.validate!

      installation = existing_installation(tenant) ||
                     AzureDevopsInstallation.new(company: company, tenant_id: tenant.tenant_id,
                                                 organization_slug: tenant.organization)
      installation.client_id = app.client_id
      installation.app_config_key = "default"
      installation.allowed_project_ids = (installation.allowed_project_ids | project_ids)
      installation.approved_by = actor
      installation.approved_at ||= Time.current
      installation.save!
      installation
    end

    # The `oid` claim of an app-only token is the service principal's object id
    # in the tenant that issued it. Reading it is not token validation — we are
    # the audience and we just obtained it over TLS from Entra — so the
    # signature is not re-checked here.
    def service_principal_object_id(installation)
      token = AppTokenService.new(installation).access_token(force: true).value
      payload = token.split(".")[1].to_s
      claims = JSON.parse(Base64.urlsafe_decode64(payload + ("=" * ((4 - payload.length % 4) % 4))))
      oid = claims["oid"].presence
      raise Error.new("Entra issued a token without an oid claim", code: "unexpected_token") if oid.blank?

      oid
    rescue JSON::ParserError, ArgumentError
      raise Error.new("Could not read the application's identity from its token", code: "unexpected_token")
    end

    # Adds the application to the organization with a Basic license and
    # Contributor access to the chosen projects — the same thing an
    # administrator would do by hand under Organization settings → Users.
    #
    # An application already entitled comes back as a failed operation rather
    # than an error status, which is the normal case on a re-run.
    def entitle!(organization:, personal_access_token:, principal_object_id:, project_ids:)
      body = {
        accessLevel: { accountLicenseType: BASIC_LICENSE },
        servicePrincipal: { origin: "aad", originId: principal_object_id, subjectKind: "servicePrincipal" },
        projectEntitlements: project_ids.map do |id|
          { group: { groupType: "projectContributor" }, projectRef: { id: id } }
        end
      }

      response = Faraday.new(url: ENTITLEMENTS_HOST) { |f| transport(f) }
                        .post("/#{ERB::Util.url_encode(organization)}/_apis/serviceprincipalentitlements") do |req|
        req.headers["Authorization"] = "Basic #{Base64.strict_encode64(":#{personal_access_token}")}"
        req.headers["Content-Type"] = "application/json"
        req.params["api-version"] = ENTITLEMENTS_VERSION
        req.body = body.to_json
      end

      return if response.status == 200

      # Same browser-shaped refusal as in OwnershipProof: a redirect or an HTML
      # body means the token was rejected, not that the request was malformed.
      if (300..399).cover?(response.status) || response.headers["content-type"].to_s.include?("text/html")
        raise NotAuthorized, "That personal access token is not valid for '#{organization}'"
      end
      raise NotAuthorized, "That token cannot add the application to '#{organization}'" if response.status == 403

      raise Error.new("Azure refused to add the application to the organization (#{response.status})",
                      code: "entitlement_failed", status: response.status)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise Error.new("Could not reach Azure DevOps (#{e.class})", code: "azure_unreachable")
    end

    def grant_service_hook_permission(installation, principal_object_id, personal_access_token, project_ids)
      ServiceHookGrant.new(
        organization: installation.organization_slug,
        personal_access_token: personal_access_token,
        tenant_id: installation.tenant_id,
        principal_object_id: principal_object_id
      ).call(project_ids)
    rescue Error => e
      @logger.warn("[AzureDevops::Onboarding] Service Hooks permission not granted for " \
                   "#{installation.organization_slug}: #{e.code}")
    end

    def confirm_application_access!(installation, project_ids)
      credential = CredentialProvider::Resolved.new(
        integration: nil, installation: installation, mode: :service_principal,
        organization: installation.organization_slug, project_id: nil,
        token_service: AppTokenService.new(installation)
      )
      client = Client.new(credential: credential, organization: installation.organization_slug)

      visible, = client.paginate("_apis", "projects", family: :core, limit: 200, params: { "$top" => 100 })
      visible_ids = visible.map { |p| p["id"] }
      missing = project_ids - visible_ids
      return if missing.empty?

      # Entitlement is not instant in every organization, and a project the
      # application still cannot see is a binding that would fail on first use.
      raise Error.new(
        "The application was added to '#{installation.organization_slug}' but cannot read " \
        "#{missing.size} of the chosen projects yet. Azure sometimes takes a moment — try again shortly.",
        code: "entitlement_not_effective"
      )
    end

    def transport(faraday)
      faraday.options.open_timeout = AppConfig.open_timeout
      faraday.options.timeout = AppConfig.read_timeout
      faraday.adapter Faraday.default_adapter
    end
  end
end
