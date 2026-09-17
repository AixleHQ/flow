# frozen_string_literal: true

module Youtrack
  class IntegrationService
    def initialize(company:, connected_by:, project: nil)
      @company, @connected_by, @project = company, connected_by, project
    end

    def create(base_url:, permanent_token:, youtrack_project_id:, webhook_header:, webhook_token:, name: nil)
      integration = @company.integrations.build(provider: :youtrack, project: @project, connected_by: @connected_by,
        name: name.presence || "YouTrack (unverified)", status: :error)
      normalized = base_url.to_s.strip.chomp("/")
      integration.credentials_data = { permanent_token: permanent_token.to_s }
      integration.settings = { "base_url" => normalized, "youtrack_project_id" => youtrack_project_id.to_s,
        "webhook_header" => webhook_header.presence || "X-YouTrack-Token" }
      errors = UrlSafetyValidator.errors_for(normalized, require_https: true)
      raise Client::Error, "YouTrack URL #{errors.first}" if errors.any?
      raise Client::Error, "Webhook token must be at least 32 characters" if webhook_token.to_s.length < 32

      client = Client.new(integration)
      me = client.get("/api/users/me", fields: "id,login,name")
      remote_project = client.get("/api/admin/projects/#{CGI.escapeURIComponent(youtrack_project_id.to_s)}",
        fields: "id,name,shortName")
      integration.name = name.presence || "YouTrack (#{remote_project['shortName']})"
      integration.status = :active
      integration.settings.merge!("project_name" => remote_project["name"], "project_short_name" => remote_project["shortName"],
        "bot_user_id" => me["id"], "bot_login" => me["login"], "last_verified_at" => Time.current.iso8601)
      Integration.transaction do
        integration.save!
        endpoint = WebhookEndpoint.create!(company: @company, project: @project, created_by: @connected_by,
          provider: :youtrack, verification_strategy: :shared_token, slug: SecureRandom.urlsafe_base64(32),
          config: { "integration_id" => integration.id, "header" => integration.settings["webhook_header"] })
        endpoint.secret = webhook_token
        endpoint.save!
      end
      integration
    rescue Client::Error => e
      integration.settings = integration.settings.merge("error" => e.message)
      integration.save!
      integration
    end
  end
end
