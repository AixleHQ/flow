# frozen_string_literal: true

module AzureDevops
  # Creates and verifies the approved company→organization binding.
  #
  # Core-release onboarding is operator-assisted on purpose. Self-service would
  # need authenticated proof that the requester controls the Azure organization,
  # and none of the values a form can collect is that proof: a tenant id, an
  # organization URL and the shared client id are all public or guessable, and
  # Microsoft explicitly warns that the `tenant` field returned by an
  # admin-consent callback must not be used to authorize anyone.
  class InstallationService
    def initialize(company:, approved_by: nil)
      @company = company
      @approved_by = approved_by
    end

    attr_reader :company, :approved_by

    # Provision (or find) the binding. Idempotent on the identity triple so a
    # repeated onboarding run does not create a second row for one organization.
    def provision!(tenant_id:, organization_slug:, app_config_key: "default", allowed_project_ids: [])
      AppConfig.fetch(app_config_key).validate!

      installation = AzureDevopsInstallation.find_or_initialize_by(
        company: company,
        tenant_id: tenant_id.to_s.strip.downcase,
        organization_slug: organization_slug.to_s.strip
      )
      installation.client_id = AppConfig.fetch(app_config_key).client_id
      installation.app_config_key = app_config_key
      installation.allowed_project_ids = Array(allowed_project_ids).map(&:to_s).uniq
      installation.approved_by = approved_by
      installation.approved_at ||= Time.current
      installation.save!
      installation
    end

    # Prove the application can actually reach the organization, and record what
    # it found. A successful token exchange alone says nothing about Azure
    # DevOps access: the principal still has to have been added to the
    # organization and given a license.
    def verify!(installation)
      client = Client.new(credential: verification_credential(installation), organization: installation.organization_slug)
      projects, = client.paginate("_apis", "projects", family: :core, limit: 200, params: { "$top" => 100 })

      installation.assign_attributes(
        status: :active,
        error_code: nil,
        last_verified_at: Time.current
      )
      installation.save!(validate: false)
      { status: :active, projects: projects.map { |p| project_summary(p) } }
    rescue CredentialActionRequired => e
      record_failure(installation, "credential_action_required")
      raise e
    rescue PermissionDenied, NotAuthorized => e
      # The app authenticated and Azure still refused. That is the onboarding
      # gap — the principal was never added to the organization, or it has no
      # license — not a credential problem, and it must not send an operator
      # rotating a working certificate.
      record_failure(installation, "installation_access_denied")
      raise NotAuthorized.new(
        "The application is not authorized in Azure DevOps organization '#{installation.organization_slug}'. " \
        "Add the tenant's service principal to the organization and assign at least a Basic access level.",
        details: e.message
      )
    rescue Error => e
      record_failure(installation, e.code)
      raise e
    end

    # Projects this installation may expose: the intersection of what Azure
    # returns and what the operator approved. Azure's answer alone would let an
    # organization-wide principal pull in projects nobody signed off on.
    def approved_projects(installation)
      client = Client.new(credential: verification_credential(installation), organization: installation.organization_slug)
      projects, = client.paginate("_apis", "projects", family: :core, limit: 200, params: { "$top" => 100 })

      projects.filter_map do |p|
        next unless installation.approved_project?(p["id"])

        project_summary(p)
      end
    end

    private

    def verification_credential(installation)
      CredentialProvider::Resolved.new(
        integration: nil, installation: installation, mode: :service_principal,
        organization: installation.organization_slug, project_id: nil,
        token_service: AppTokenService.new(installation)
      )
    end

    def project_summary(project)
      {
        id: project["id"],
        name: project["name"],
        description: project["description"],
        visibility: project["visibility"],
        state: project["state"]
      }
    end

    def record_failure(installation, code)
      installation.assign_attributes(status: :error, error_code: code.to_s, last_verified_at: Time.current)
      installation.save!(validate: false)
    end
  end
end
