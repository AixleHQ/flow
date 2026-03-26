# frozen_string_literal: true

module Github
  class IntegrationService
    class ConfigurationError < StandardError; end
    class AuthenticationError < StandardError; end

    def initialize(company:, connected_by:, project: nil)
      @company = company
      @connected_by = connected_by
      @project = project
    end

    def create(installation_id:)
      integration = @company.integrations.new(
        provider: :github,
        connected_by: @connected_by,
        status: :inactive,
        project: @project
      )
      integration.credentials_data = { installation_id: installation_id.to_s }

      begin
        info = Github::TokenService.new(integration).verify_installation
        integration.name = info[:account_login]
        integration.settings = {
          account_type: info[:account_type],
          target_type: info[:target_type]
        }
        integration.status = :active
      rescue Github::TokenService::ConfigurationError, Github::TokenService::AuthenticationError => e
        integration.name = "GitHub (unverified)" if integration.name.blank?
        integration.status = :error
        integration.settings = { error: e.message }
      end

      integration.save
      integration
    end
  end
end
