# frozen_string_literal: true

module AzureDevops
  # Creates, tests, repairs and disconnects the PROJECT connection — the record
  # that says "this Aixle project works against this one Azure project".
  #
  # Mirrors Github::IntegrationService's shape (build, verify, persist with a
  # status) so the integrations page needs no special case, but the verification
  # is different in kind: GitHub verifies an installation the user just
  # authorized, while here the application's access was established out of band
  # and what needs proving is that the SELECTED PROJECT is reachable and
  # approved.
  class IntegrationService
    # Everything a connection may be permitted to do.
    ALL_CAPABILITIES = %w[
      repositories.read repositories.write
      pull_requests.write pull_request_threads.write
      work_items.read work_items.write
      pull_requests.complete builds.read
    ].freeze

    # What a new connection gets. Completing pull requests is deliberately NOT
    # among them: merging is the one agent action nobody should acquire by
    # accepting a form's defaults, so it is switched on explicitly or not at all.
    DEFAULT_CAPABILITIES = (ALL_CAPABILITIES - %w[pull_requests.complete]).freeze

    class ConfigurationError < StandardError; end

    def initialize(company:, connected_by:, project:)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    attr_reader :company, :connected_by, :project

    # Service-principal mode: bind an already-approved installation to one
    # Azure project. The project id arrives from the browser, so it is checked
    # against the approved scope and then against Azure itself — never trusted.
    def create_with_installation(installation_id:, azure_project_id:, enabled_capabilities: nil)
      installation = AzureDevopsInstallation.find_by(id: installation_id, company_id: company.id)
      raise ConfigurationError, "No approved Azure organization installation for this company" if installation.nil?
      raise ConfigurationError, "The Azure organization installation is disabled" unless installation.active?
      unless installation.approved_project?(azure_project_id)
        raise ConfigurationError, "That Azure project is not in the approved scope for this organization"
      end

      integration = build_integration(
        installation: installation,
        settings: {
          "auth_mode" => "service_principal",
          "organization_slug" => installation.organization_slug,
          "organization_id" => installation.organization_id,
          "tenant_id" => installation.tenant_id,
          "client_id" => installation.client_id,
          "service_principal_object_id" => installation.service_principal_object_id,
          "azure_project_id" => azure_project_id.to_s,
          "enabled_capabilities" => Array(enabled_capabilities).presence || DEFAULT_CAPABILITIES
        }
      )

      activate(integration)
    end

    # PAT mode. A different identity: operations act as the token's owner and
    # carry that person's upstream permissions, so it is labelled separately
    # everywhere and is never selected automatically when app setup fails.
    def create_with_pat(organization_slug:, azure_project_id:, personal_access_token:, enabled_capabilities: nil)
      raise ConfigurationError, "PAT mode is not enabled on this deployment" unless AppConfig.pat_mode_enabled?
      raise ConfigurationError, "A personal access token is required" if personal_access_token.blank?

      integration = build_integration(
        installation: nil,
        settings: {
          "auth_mode" => "pat",
          "organization_slug" => organization_slug.to_s.strip,
          "azure_project_id" => azure_project_id.to_s,
          "enabled_capabilities" => Array(enabled_capabilities).presence || DEFAULT_CAPABILITIES
        }
      )
      integration.credentials_data = { "personal_access_token" => personal_access_token.to_s }

      activate(integration)
    end

    # Re-verify an existing connection without touching its id or repository
    # attachments, and without replacing a working credential when the check
    # fails. `test` never mutates Azure.
    def test(integration)
      project_info = verify_selected_project!(integration)
      integration.settings = integration.settings.to_h.merge(
        "azure_project_name" => project_info[:name],
        "identity_display_name" => project_info[:identity_display_name],
        "last_verified_at" => Time.current.iso8601
      ).compact
      integration.status = :active
      integration.save!
      { status: :active, project: project_info }
    rescue Error => e
      mark_error(integration, e)
      { status: :error, error: e.code, message: e.message }
    end

    # PAT replacement. The new token is verified BEFORE it replaces the old one:
    # a failed rotation must leave a working connection working.
    def replace_pat(integration, personal_access_token:)
      raise ConfigurationError, "This connection does not use a personal access token" unless integration.azure_pat?
      raise ConfigurationError, "A personal access token is required" if personal_access_token.blank?

      candidate = integration.dup
      candidate.credentials_data = { "personal_access_token" => personal_access_token.to_s }
      verify_selected_project!(candidate)

      integration.credentials_data = { "personal_access_token" => personal_access_token.to_s }
      integration.status = :active
      integration.settings = integration.settings.to_h.merge("last_verified_at" => Time.current.iso8601)
      integration.save!
      integration
    end

    # Disconnecting one project connection blocks its new token requests and
    # API calls and follows the existing repository detach behaviour. It does
    # NOT disable the shared installation, delete the tenant's service
    # principal, or rotate the central app credential other connections use.
    def disconnect(integration)
      # Cleanup runs FIRST, while this connection's credentials still resolve —
      # after the row is gone there is nothing left to authenticate with, and the
      # subscription would keep posting to an endpoint that no longer exists.
      # Failure is logged, not raised: a disconnect must not be blocked by it,
      # and what is left behind fails closed.
      SubscriptionService.new(integration).remove_all! if integration.azure_devops_subscriptions.any?
      integration.destroy!
    end

    private

    def build_integration(installation:, settings:)
      integration = company.integrations.new(
        provider: :azure_devops,
        connected_by: connected_by,
        project: project,
        status: :inactive,
        azure_devops_installation: installation,
        settings: settings
      )
      integration.name = settings["organization_slug"].presence || "Azure DevOps"
      integration
    end

    def activate(integration)
      info = verify_selected_project!(integration)
      integration.name = "#{integration.settings['organization_slug']}/#{info[:name]}"
      integration.settings = integration.settings.to_h.merge(
        "azure_project_name" => info[:name],
        "identity_display_name" => info[:identity_display_name],
        "last_verified_at" => Time.current.iso8601
      ).compact
      integration.status = :active
      integration.save!
      integration
    rescue Error => e
      # Persist the failure so the card can explain it, but keep the connection
      # inactive: a row that looks connected and cannot reach Azure is worse
      # than a visible error.
      integration.name = integration.name.presence || "Azure DevOps (unverified)"
      integration.status = :error
      integration.settings = integration.settings.to_h.merge("error" => e.code, "error_message" => e.message)
      integration.save
      raise ConfigurationError, e.message
    end

    # The one check that matters at connect time: the selected project must be
    # readable through this exact connection. A token that Entra issued proves
    # the app authenticated, not that this project exists or is permitted.
    def verify_selected_project!(integration)
      # allow_inactive: this IS the check that decides whether the connection
      # becomes active. Requiring active here would make a new connection
      # unverifiable and a repair impossible once one had errored.
      client, resolved = CredentialProvider.client_for(integration, allow_inactive: true)
      project_id = integration.azure_project_id
      raise ConfigurationError, "No Azure project selected" if project_id.blank?

      payload = client.get("_apis", "projects", project_id, family: :core)

      # Azure answering about a DIFFERENT project than the one asked for would
      # mean the id was resolved by name somewhere; refuse rather than record it.
      if payload["id"].present? && payload["id"] != project_id
        raise ValidationFailed, "Azure returned a different project than the one selected"
      end

      { id: payload["id"], name: payload["name"], identity_display_name: identity_name(resolved) }
    end

    # Best-effort: who Azure thinks we are, for the connection card. A failure
    # here is cosmetic and must not fail the connection.
    def identity_name(resolved)
      return nil unless resolved.service_principal?

      "Aixle (#{resolved.installation.client_id.to_s.first(8)}…)"
    rescue StandardError
      nil
    end

    def mark_error(integration, error)
      integration.status = :error
      integration.settings = integration.settings.to_h.merge("error" => error.code, "error_message" => error.message)
      integration.save!
    end
  end
end
