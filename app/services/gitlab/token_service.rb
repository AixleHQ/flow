# frozen_string_literal: true

module Gitlab
  class TokenService
    class ConfigurationError < StandardError; end
    class AuthenticationError < StandardError; end

    def initialize(integration)
      @integration = integration
    end

    def client
      ::Gitlab.client(
        endpoint: gitlab_endpoint,
        private_token: personal_access_token
      )
    end

    def verify_token
      user = client.user
      { id: user.id, username: user.username, name: user.name, email: user.email }
    rescue ::Gitlab::Error::Unauthorized, ::Gitlab::Error::Forbidden => e
      raise AuthenticationError, "GitLab token verification failed: #{e.message}"
    end

    private

    def personal_access_token
      @integration.credentials_data["personal_access_token"] ||
        raise(ConfigurationError, "GitLab personal_access_token not configured")
    end

    def gitlab_endpoint
      Settings.gitlab.endpoint.presence || "https://gitlab.com/api/v4"
    end
  end
end
