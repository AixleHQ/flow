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

    # Capability lists arrive from the browser and land in `settings`, which
    # IntegrationResource serializes whole — so an unrecognized entry would be
    # persisted and echoed back to every viewer. Intersecting here rather than in
    # the controller means every caller gets it, not just the one door.
    #
    # `nil` means "the caller did not say" and takes the defaults; an explicit
    # empty list means "nothing", which is a connection that can be attached and
    # can do nothing until it is edited.
    def self.sanitize_capabilities(requested)
      return DEFAULT_CAPABILITIES if requested.nil?

      Array(requested).map(&:to_s) & ALL_CAPABILITIES
    end

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
          "enabled_capabilities" => self.class.sanitize_capabilities(enabled_capabilities)
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
          "enabled_capabilities" => self.class.sanitize_capabilities(enabled_capabilities)
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
      apply_verified(integration, project_info)
      { status: :active, project: project_info }
    rescue Error => e
      record_error(integration, e.code)
      # The message goes to the caller, which puts it in a flash — not into
      # `settings`, which reaches every viewer of the integrations page.
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
      integration.settings = integration.settings.to_h
                                        .merge("last_verified_at" => Time.current.iso8601)
                                        .except("error", "error_message")
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
      apply_verified(integration, info)
      provision_subscriptions(integration)
      integration
    rescue Error => e
      # Persist the failure so the card can explain it, but keep the connection
      # inactive: a row that looks connected and cannot reach Azure is worse
      # than a visible error.
      integration.name = integration.name.presence || "Azure DevOps (unverified)"
      record_error(integration, e.code)
      raise ConfigurationError, e.message
    end

    # A successful verification CLEARS the recorded error. Without this a
    # connection that failed once and was then repaired keeps shipping the old
    # error code to the browser while reporting itself active.
    def apply_verified(integration, info)
      integration.settings = integration.settings.to_h.merge(
        "azure_project_name" => info[:name],
        "identity_display_name" => info[:identity_display_name],
        "last_verified_at" => Time.current.iso8601
      ).compact.except("error", "error_message")
      integration.status = :active
      integration.save!
    end

    # Service Hooks, best effort and after the connection is already active.
    # Creating them needs organization-level permission this connection may not
    # have, and everything on demand works without them — so a failure is logged
    # and the subscription row carries its own error, rather than failing a
    # connection that is otherwise fine. `rake azure_devops:hooks` retries.
    def provision_subscriptions(integration)
      return unless AppConfig.webhooks_enabled?

      SubscriptionService.new(integration).ensure_all!
    rescue StandardError => e
      Rails.logger.warn("[AzureDevops::IntegrationService] subscription setup skipped for " \
                        "integration #{integration.id}: #{e.class}: #{e.message}")
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

    # Only the adapter's own stable CODE is recorded. IntegrationResource
    # serializes `settings` to the browser whole and says so in its own comment:
    # raw provider errors do not belong there, and Azure's envelope text can
    # name identities, policies and project structure.
    #
    # Saved WITHOUT validation on purpose. The commonest way to land here is a
    # connection whose Azure project has left the installation's approved scope
    # — which is exactly what `azure_devops_connection_is_scoped` rejects — so
    # `save!` would raise out of the error handler and turn a reportable failure
    # into a 500.
    def record_error(integration, code = nil)
      integration.status = :error
      integration.settings = integration.settings.to_h.merge("error" => code).compact
      return if integration.save(validate: false)

      Rails.logger.error("[AzureDevops::IntegrationService] could not record the failure on " \
                         "integration #{integration.id}")
    end
  end
end
