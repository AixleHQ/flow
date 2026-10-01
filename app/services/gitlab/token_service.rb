# frozen_string_literal: true

module Gitlab
  class TokenService
    class ConfigurationError < StandardError; end
    class AuthenticationError < StandardError; end
    # GitLab could not be asked at all: it is unreachable, or GITLAB_ENDPOINT
    # does not point at a GitLab API. Nothing is known about the token.
    class ConnectionError < StandardError; end

    NETWORK_ERRORS = [
      SocketError, SystemCallError, Timeout::Error, IOError, OpenSSL::SSL::SSLError, HTTParty::Error, URI::Error
    ].freeze

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
    rescue ::Gitlab::Error::Unauthorized
      raise AuthenticationError, "GitLab rejected this token. It is mistyped, expired or revoked."
    rescue ::Gitlab::Error::Forbidden
      raise AuthenticationError, "GitLab refused this token. Create one with the api scope."
    rescue ::Gitlab::Error::Error
      raise ConnectionError, "#{gitlab_endpoint} did not answer as a GitLab API. " \
                             "The operator should check GITLAB_ENDPOINT, which ends in /api/v4."
    rescue *NETWORK_ERRORS => e
      raise ConnectionError, "Could not reach GitLab at #{gitlab_endpoint} (#{e.class.name.demodulize})."
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
