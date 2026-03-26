# frozen_string_literal: true

module Gitlab
  class IntegrationService
    class ConfigurationError < StandardError; end
    class AuthenticationError < StandardError; end

    def initialize(company:, connected_by:, project: nil)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    def create(personal_access_token:)
      integration = Integration.find_or_build_gitlab_for_token(
        company: @company,
        connected_by: @connected_by,
        project: @project
      )
      integration.credentials_data = { personal_access_token: personal_access_token.to_s }

      begin
        info = Gitlab::TokenService.new(integration).verify_token
        integration.name = info[:username]
        integration.status = :active
      rescue Gitlab::TokenService::ConfigurationError, Gitlab::TokenService::AuthenticationError => e
        integration.name = "GitLab (unverified)" if integration.name.blank?
        integration.status = :error
        integration.settings = { error: e.message }
      end

      integration.save
      integration
    end
  end
end
