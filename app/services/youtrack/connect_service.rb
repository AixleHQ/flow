# frozen_string_literal: true

module Youtrack
  class ConnectService < Integrations::ConnectService
    HEADER_NAME = /\A[A-Za-z0-9!#$%&'*+.^_`|~-]+\z/

    def create(base_url:, permanent_token:, youtrack_project_id:, webhook_header:, webhook_token:, name: nil)
      connect(base_url: base_url, permanent_token: permanent_token, youtrack_project_id: youtrack_project_id,
        webhook_header: webhook_header, webhook_token: webhook_token, name: name)
    end

    def rotate_webhook!(integration:, webhook_header:, webhook_token:)
      raise Integrations::VerificationError, "Not a YouTrack connection" unless integration.youtrack?
      header = webhook_header.to_s.strip
      validate_webhook!(header, webhook_token)
      endpoint = integration.youtrack_webhook_endpoint
      raise Integrations::VerificationError, "Webhook endpoint is missing" unless endpoint
      Integration.transaction do
        endpoint.update!(secret: webhook_token, config: endpoint.config.merge("header" => header))
        integration.update!(settings: integration.settings.merge("webhook_header" => header))
      end
      integration
    end

    private

    def provider = :youtrack
    def credentials(params) = { permanent_token: params[:permanent_token].to_s }
    def settings(params)
      { "base_url" => Integrations::UrlNormalizer.call(params[:base_url]),
        "youtrack_project_id" => params[:youtrack_project_id].to_s,
        "webhook_header" => params[:webhook_header].presence || "X-YouTrack-Token" }
    end

    def verify!(integration)
      errors = UrlSafetyValidator.errors_for(integration.youtrack_base_url, require_https: true)
      raise Integrations::VerificationError, "YouTrack URL #{errors.first}" if errors.any?
      validate_webhook!(integration.settings["webhook_header"], @webhook_token)
      client = Client.new(integration)
      me = client.me
      project = client.project(integration.youtrack_project_id)
      raise Integrations::VerificationError, "YouTrack identity or project is incomplete" if me["id"].blank? || me["login"].blank? || project["id"].to_s != integration.youtrack_project_id
      integration.name = @display_name.presence || "YouTrack (#{project['shortName']})"
      integration.settings.merge!("project_name" => project["name"], "project_short_name" => project["shortName"],
        "bot_user_id" => me["id"], "bot_login" => me["login"], "last_verified_at" => Time.current.iso8601)
    rescue Client::Error => e
      raise Integrations::VerificationError, e.message
    end

    def connect(params)
      @webhook_token = params[:webhook_token]
      @display_name = params[:name]
      super
    end

    def after_connect!(integration, params)
      endpoint = WebhookEndpoint.new(company: @company, project: @project, created_by: @connected_by,
        provider: :youtrack, verification_strategy: :shared_token, slug: SecureRandom.urlsafe_base64(32),
        config: { "integration_id" => integration.id, "header" => integration.settings["webhook_header"] })
      endpoint.secret = params[:webhook_token]
      endpoint.save!
    end

    def validate_webhook!(header, token)
      raise Integrations::VerificationError, "Invalid webhook header" unless header.to_s.match?(HEADER_NAME)
      raise Integrations::VerificationError, "Webhook token must be at least 32 characters" if token.to_s.length < 32
    end
  end
end
