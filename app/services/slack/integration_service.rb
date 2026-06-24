# frozen_string_literal: true

module Slack
  # Connects a Slack integration for a (company, project) pair and provisions the
  # inbound webhook endpoint Slack will POST events to. Persists the integration
  # in :active (secret stored, endpoint created) or :error state either way, so
  # the user can repair from the integrations page. Mirrors the Coder/GitLab pattern.
  class IntegrationService
    def initialize(company:, connected_by:, project: nil)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    def create(workspace_name:, signing_secret:)
      integration = build_integration
      integration.name = workspace_name.presence || "Slack"
      integration.credentials_data = { signing_secret: signing_secret.to_s }

      if signing_secret.blank?
        return save_error(integration, "Signing secret is required")
      end

      integration.status = :active
      integration.save!

      endpoint = provision_endpoint(integration, signing_secret)
      integration.update!(settings: integration.settings.to_h.merge(
        "webhook_endpoint_id" => endpoint.id,
        "request_url" => request_url(endpoint.slug)
      ))
      integration
    rescue ActiveRecord::RecordInvalid => e
      save_error(integration, e.message)
    end

    private

    def build_integration
      @company.integrations.build(provider: :slack, connected_by: @connected_by, project: @project)
    end

    def provision_endpoint(integration, signing_secret)
      WebhookEndpoint.create!(
        slug: "slack-#{integration.id}",
        provider: :slack,
        verification_strategy: :slack_v0,
        secret: signing_secret.to_s,
        project: @project,
        company: @company,
        created_by: @connected_by
      )
    end

    def request_url(slug)
      "https://#{Settings.domain}/webhooks/in/#{slug}"
    end

    def save_error(integration, message)
      integration.status = :error
      integration.settings = integration.settings.to_h.merge("error" => message)
      integration.save
      integration
    end
  end
end
