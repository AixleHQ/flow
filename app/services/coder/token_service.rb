# frozen_string_literal: true

module Coder
  # HTTP client + token verification against a Coder instance.
  #
  # Reads the URL and session token from the integration's encrypted
  # credentials. The `verify_token` method calls `GET /api/v2/users/me` and
  # returns `{id, username, email}` on success.
  #
  # Raises:
  #   - ConfigurationError when URL or token is missing from credentials.
  #   - AuthenticationError on 4xx/5xx, timeouts, transport errors, or invalid JSON.
  class TokenService
    class ConfigurationError < StandardError; end
    class AuthenticationError < StandardError; end

    HTTP_TIMEOUTS = { open: 10, read: 30 }.freeze
    SESSION_TOKEN_HEADER = "Coder-Session-Token"

    def initialize(integration)
      @integration = integration
    end

    def verify_token
      response = http_get("/api/v2/users/me")

      case response.status
      when 200
        body = JSON.parse(response.body.to_s)
        { id: body["id"], username: body["username"], email: body["email"] }
      else
        raise AuthenticationError, "Coder token verification failed: HTTP #{response.status}"
      end
    rescue JSON::ParserError
      raise AuthenticationError, "Coder token verification failed: invalid JSON response"
    rescue Faraday::Error => e
      # Strip the token from any error message, defense-in-depth.
      raise AuthenticationError, "Coder token verification failed: #{redact(e.message)}"
    end

    private

    def http_get(path)
      conn.get(path)
    end

    def conn
      @conn ||= Faraday.new(url: coder_url) do |f|
        f.options.open_timeout = HTTP_TIMEOUTS[:open]
        f.options.timeout      = HTTP_TIMEOUTS[:read]
        f.headers[SESSION_TOKEN_HEADER] = session_token
        f.headers["Accept"] = "application/json"
      end
    end

    def coder_url
      @integration.credentials_data["coder_url"].presence ||
        raise(ConfigurationError, "Coder URL not configured")
    end

    def session_token
      @integration.credentials_data["session_token"].presence ||
        raise(ConfigurationError, "Coder session_token not configured")
    end

    def redact(message)
      token = @integration.credentials_data["session_token"].to_s
      return message.to_s if token.empty?

      message.to_s.gsub(token, "[REDACTED]")
    end
  end
end
