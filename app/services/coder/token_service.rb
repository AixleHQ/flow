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
      @conn ||= build_conn
    end

    # Build the Faraday connection. When the configured Coder host is in the
    # trusted-hosts allowlist (split-horizon DNS scenario) the system resolver
    # may return a private IP that is not reachable from inside the cluster;
    # in that case fall back to a public DNS lookup and connect to the public
    # IP directly while preserving the original hostname for the Host header
    # and TLS SNI.
    def build_conn
      uri = URI.parse(coder_url)
      target_url, sni_hostname, host_header = resolve_target(uri)

      ssl_opts = sni_hostname ? { hostname: sni_hostname } : {}
      Faraday.new(url: target_url, ssl: ssl_opts) do |f|
        f.options.open_timeout = HTTP_TIMEOUTS[:open]
        f.options.timeout      = HTTP_TIMEOUTS[:read]
        f.headers[SESSION_TOKEN_HEADER] = session_token
        f.headers["Accept"] = "application/json"
        f.headers["Host"] = host_header if host_header
      end
    end

    def resolve_target(uri)
      return [ uri.to_s, nil, nil ] unless UrlSafetyValidator.trusted_host?(uri.host.to_s)

      public_ip = UrlSafetyValidator.resolve_public_ipv4(uri.host)
      return [ uri.to_s, nil, nil ] if public_ip.nil?

      rewritten = uri.dup
      rewritten.host = public_ip

      port = uri.port
      host_header = port == uri.default_port ? uri.host : "#{uri.host}:#{port}"
      [ rewritten.to_s, uri.host, host_header ]
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
