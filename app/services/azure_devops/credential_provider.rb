# frozen_string_literal: true

module AzureDevops
  # Resolves one integration into usable Azure authentication, and is the single
  # place that decides whether it is allowed to.
  #
  # The authorization question here is NOT "can the application reach this
  # organization" — an app-only token proves that and proves nothing about who
  # is asking. It is "does this Aixle company hold an approved binding to this
  # organization, is this integration still active, and is the selected Azure
  # project still inside that binding's approved scope". Discovery, tool
  # execution and Git credential issuance all pass through here.
  class CredentialProvider
    Resolved = Struct.new(:integration, :installation, :mode, :organization, :project_id, :token_service,
                          keyword_init: true) do
      # Entra Git auth and the REST API both take a bearer header; PAT mode uses
      # Basic with an empty username. These are Microsoft's two documented
      # shapes and they are not interchangeable.
      def authorization_headers
        case mode
        when :service_principal then { "Authorization" => "Bearer #{token_service.access_token.value}" }
        when :pat then { "Authorization" => "Basic #{Base64.strict_encode64(":#{integration.azure_personal_access_token}")}" }
        end
      end

      # Git-side material. Kept separate from the header form because the Git
      # credential helper needs the raw parts, and because the expiry has to
      # travel with it for a long session to renew on time.
      def git_credential
        case mode
        when :service_principal
          token = token_service.access_token
          { scheme: "bearer", token: token.value, expires_in: token.expires_in }
        when :pat
          { scheme: "basic", username: "", token: integration.azure_personal_access_token, expires_in: nil }
        end
      end

      def invalidate!
        token_service&.refresh_after_unauthorized! if mode == :service_principal
      end

      def service_principal? = mode == :service_principal
    end

    class << self
      # `capability` is the Aixle operation profile name (see §5.4). It is
      # checked BEFORE any Azure request, so a connection with Boards writes
      # switched off never reaches Azure to be told no.
      #
      # `allow_inactive` exists for exactly one caller: the connect and repair
      # flow, which has to reach Azure in order to decide whether the connection
      # should become active at all. Everything else — tool execution, git
      # credential vending, repository discovery — leaves it false, so a
      # disconnected or errored connection stops working immediately.
      def resolve!(integration, capability: nil, allow_inactive: false)
        raise IntegrationUnavailable, "Azure DevOps is not enabled on this deployment" unless AppConfig.enabled?
        raise IntegrationUnavailable, "Integration is not an Azure DevOps connection" unless integration&.azure_devops?
        raise IntegrationUnavailable, "Integration is not active" unless allow_inactive || integration.active?

        if capability.present? && !integration.azure_capability_enabled?(capability)
          raise NotAuthorized, "This connection does not enable #{capability}"
        end

        integration.azure_pat? ? resolve_pat(integration) : resolve_service_principal(integration)
      end

      private

      def resolve_service_principal(integration)
        installation = integration.azure_devops_installation
        raise NotAuthorized, "No approved Azure organization installation for this connection" if installation.nil?
        raise NotAuthorized, "The approved installation belongs to another company" if installation.company_id != integration.company_id
        raise IntegrationUnavailable, "The Azure organization installation is disabled" unless installation.active?

        project_id = integration.azure_project_id
        unless installation.approved_project?(project_id)
          raise NotAuthorized, "Azure project #{project_id} is not in this installation's approved scope"
        end

        Resolved.new(
          integration: integration, installation: installation, mode: :service_principal,
          organization: installation.organization_slug, project_id: project_id,
          token_service: AppTokenService.new(installation)
        )
      end

      def resolve_pat(integration)
        raise IntegrationUnavailable, "PAT mode is not enabled on this deployment" unless AppConfig.pat_mode_enabled?
        raise CredentialActionRequired, "This connection has no stored personal access token" if integration.azure_personal_access_token.blank?

        organization = integration.azure_organization_slug
        raise IntegrationUnavailable, "This connection has no Azure organization" if organization.blank?

        Resolved.new(
          integration: integration, installation: nil, mode: :pat,
          organization: organization, project_id: integration.azure_project_id, token_service: nil
        )
      end
    end

    # Convenience: a ready client for the resolved connection, scoped to its
    # selected Azure project. Callers never choose the organization themselves.
    def self.client_for(integration, capability: nil, allow_inactive: false)
      resolved = resolve!(integration, capability: capability, allow_inactive: allow_inactive)
      [ Client.new(credential: resolved, organization: resolved.organization), resolved ]
    end
  end
end
