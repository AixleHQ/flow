# frozen_string_literal: true

module Coder
  # TokenService — verifies a Coder integration's session token by reading
  # credentials from the encrypted blob and delegating the HTTP call to
  # `Coder::Api`. The service owns integration-level concerns (credential
  # presence checks, token redaction in error messages) but no transport
  # details — those live in `Coder::Api`.
  #
  # Raises:
  #   - ConfigurationError when URL or token is missing from credentials.
  #   - AuthenticationError on any failure from the API layer (HTTP error,
  #     transport error, timeout, invalid JSON), with the integration's
  #     session token redacted from the message.
  class TokenService
    class ConfigurationError < StandardError; end
    class AuthenticationError < StandardError; end

    def initialize(integration)
      @integration = integration
    end

    def verify_token
      Coder::Api.verify_token(coder_url: coder_url, session_token: session_token)
    rescue Coder::Api::ApiError => e
      raise AuthenticationError, "Coder token verification failed: #{redact(e.message)}"
    end

    def coder_url
      @integration.credentials_data["coder_url"].presence ||
        raise(ConfigurationError, "Coder URL not configured")
    end

    def session_token
      @integration.credentials_data["session_token"].presence ||
        raise(ConfigurationError, "Coder session_token not configured")
    end

    # Redact the integration's session token from a string (defense in depth).
    def redact(message)
      token = @integration.credentials_data["session_token"].to_s
      return message.to_s if token.empty?

      message.to_s.gsub(token, "[REDACTED]")
    end
  end
end
