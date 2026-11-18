# frozen_string_literal: true

module MCPAuth
  # Which redirect URIs a client may use. Most MCP clients are native apps
  # (Claude Code, Cursor, VS Code) or hosted assistants (claude.ai), so three
  # shapes are allowed: https anywhere, http on loopback only, and a native
  # app's private-use scheme (RFC 8252 §7.1).
  module RedirectUri
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 [::1]].freeze
    # Schemes a browser would run or read locally rather than hand to an app.
    FORBIDDEN_SCHEMES = %w[javascript data file vbscript blob about filesystem view-source ws wss ftp].freeze
    SCHEME_FORMAT = /\A[a-z][a-z0-9+.-]*\z/

    module_function

    def registrable?(value)
      uri = parse(value)
      return false if uri.nil? || uri.fragment || uri.userinfo

      case uri.scheme
      when "https" then uri.host.present?
      when "http" then loopback?(uri)
      else uri.scheme.match?(SCHEME_FORMAT) && FORBIDDEN_SCHEMES.exclude?(uri.scheme)
      end
    end

    # Exact match, except that a loopback URI matches on any port: a native app
    # binds an ephemeral one per sign-in (RFC 8252 §7.3). Claude Code declares
    # `http://localhost/callback` and then sends `http://localhost:<port>/callback`.
    def allowed?(registered, requested)
      return false unless registrable?(requested)

      Array(registered).any? { |uri| uri == requested || same_loopback_endpoint?(uri, requested) }
    end

    def loopback?(uri)
      uri.scheme == "http" && LOOPBACK_HOSTS.include?(uri.host.to_s.downcase)
    end

    # Where the browser is sent after consent, as the consent screen names it.
    def destination(value)
      uri = parse(value)
      return value.to_s if uri.nil?
      return "an app on this computer (#{uri.host})" if loopback?(uri)
      return uri.host if uri.scheme == "https"

      "an app on this computer (#{uri.scheme}:)"
    end

    def on_this_computer?(value)
      uri = parse(value)
      uri.present? && uri.scheme != "https"
    end

    def with_params(value, params)
      uri = URI.parse(value)
      query = URI.decode_www_form(uri.query.to_s) + params.compact.map { |k, v| [ k.to_s, v.to_s ] }
      uri.query = URI.encode_www_form(query)
      uri.to_s
    end

    def same_loopback_endpoint?(registered, requested)
      a = parse(registered)
      b = parse(requested)
      return false unless a && b && loopback?(a) && loopback?(b)

      a.host.downcase == b.host.downcase && a.path.presence.to_s == b.path.presence.to_s && a.query == b.query
    end

    def parse(value)
      return nil unless value.is_a?(String) && value.length <= 2048

      uri = URI.parse(value)
      uri.scheme.present? ? uri : nil
    rescue URI::InvalidURIError
      nil
    end
  end
end
