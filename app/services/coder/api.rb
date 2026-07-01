# frozen_string_literal: true

require "faraday/net_http"

module Coder
  # Coder::Api — thin HTTP API layer for a Coder instance.
  #
  # Class methods receive the connection params (`coder_url`, `session_token`)
  # explicitly. The services (`TokenService`, `WorkspaceService`) own the
  # integration record and business logic; this layer is responsible for the
  # transport, endpoint paths, request/response shape, and JSON parsing.
  #
  # Errors collapse into a small hierarchy so callers can rescue once:
  #
  #   ApiError
  #   ├── HTTPError      — non-success HTTP status (`.status` populated)
  #   ├── TransportError — Faraday-level error (connection/SSL/etc.)
  #   ├── TimeoutError   — open/read timeout
  #   └── ParseError     — invalid JSON in a response body
  class Api
    class ApiError < StandardError; end
    class TransportError < ApiError; end
    class TimeoutError < ApiError; end
    class ParseError < ApiError; end

    class HTTPError < ApiError
      attr_reader :status, :body
      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body   = body
      end
    end

    HTTP_TIMEOUTS         = { open: 10, read: 30 }.freeze
    SESSION_TOKEN_HEADER  = "Coder-Session-Token"

    # Faraday's stock net_http adapter ignores the `ssl: { hostname: }` option,
    # so pointing the connection URL at a bare IP silently drops TLS SNI — and
    # SNI-routing proxies (e.g. Traefik) then present their default self-signed
    # certificate. This adapter keeps the URL on the original hostname (which
    # is what Net::HTTP uses for SNI, certificate verification, and the Host
    # header) and overrides only the TCP target via Net::HTTP#ipaddr.
    class SniPreservingNetHttp < Faraday::Adapter::NetHttp
      def net_http_connection(env)
        super.tap do |http|
          ipaddr = @connection_options[:ipaddr]
          http.ipaddr = ipaddr if ipaddr
        end
      end
    end

    class << self
      def verify_token(coder_url:, session_token:)
        body = json_get("/api/v2/users/me", coder_url: coder_url, session_token: session_token, op: "verify_token")
        { id: body["id"], username: body["username"], email: body["email"] }
      end

      def list_workspaces(coder_url:, session_token:)
        body = json_get("/api/v2/workspaces", coder_url: coder_url, session_token: session_token, op: "list_workspaces")
        body["workspaces"] || []
      end

      def build_workspace(coder_url:, session_token:, workspace_id:, transition:)
        json_post(
          "/api/v2/workspaces/#{workspace_id}/builds",
          { transition: transition },
          coder_url: coder_url, session_token: session_token,
          op: "build_workspace", accept: [ 200, 201 ]
        )
      end

      def get_workspace_build(coder_url:, session_token:, build_id:)
        json_get(
          "/api/v2/workspacebuilds/#{build_id}",
          coder_url: coder_url, session_token: session_token, op: "get_workspace_build"
        )
      end

      def list_templates(coder_url:, session_token:)
        response = request(:get, "/api/v2/templates", coder_url: coder_url, session_token: session_token)
        return [] unless response.status == 200

        Array(parse_json(response, op: "list_templates"))
      rescue ApiError
        []
      end

      def create_workspace(coder_url:, session_token:, user_id:, name:, template_id:)
        json_post(
          "/api/v2/users/#{user_id}/workspaces",
          { name: name, template_id: template_id },
          coder_url: coder_url, session_token: session_token,
          op: "create_workspace", accept: [ 200, 201 ]
        )
      end

      private

      def json_get(path, coder_url:, session_token:, op:)
        response = request(:get, path, coder_url: coder_url, session_token: session_token)
        assert_ok!(response, op: op)
        parse_json(response, op: op)
      end

      def json_post(path, body, coder_url:, session_token:, op:, accept: [ 200 ])
        response = request(:post, path, coder_url: coder_url, session_token: session_token, body: body)
        assert_ok!(response, op: op, accept: accept)
        parse_json(response, op: op)
      end

      def request(method, path, coder_url:, session_token:, body: nil)
        conn = build_conn(coder_url, session_token)
        case method
        when :get   then conn.get(path)
        when :post  then conn.post(path) { |req| set_json_body(req, body) }
        when :patch then conn.patch(path) { |req| set_json_body(req, body) }
        else
          raise ApiError, "unsupported HTTP method: #{method.inspect}"
        end
      rescue Faraday::TimeoutError => e
        raise TimeoutError, e.message
      rescue Faraday::ConnectionFailed => e
        # faraday-net_http maps Net::OpenTimeout / Net::ReadTimeout to
        # Faraday::ConnectionFailed; both inherit from Timeout::Error.
        raise TimeoutError, e.message if e.wrapped_exception.is_a?(Timeout::Error)

        raise TransportError, e.message
      rescue Faraday::Error => e
        raise TransportError, e.message
      end

      def set_json_body(req, body)
        return if body.nil?

        req.headers["Content-Type"] = "application/json"
        req.body = body.is_a?(String) ? body : body.to_json
      end

      def assert_ok!(response, op:, accept: [ 200 ])
        return if accept.include?(response.status)

        raise HTTPError.new(
          "#{op} failed: HTTP #{response.status}",
          status: response.status, body: response.body.to_s
        )
      end

      def parse_json(response, op:)
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        raise ParseError, "#{op} failed: invalid JSON response"
      end

      # Build the Faraday connection. When the configured Coder host is in
      # the trusted-hosts allowlist (split-horizon DNS scenario) the system
      # resolver may return a private IP that is not reachable from inside
      # the cluster; in that case resolve the public IPv4 and connect to it
      # through SniPreservingNetHttp. The URL must keep the hostname — the
      # bare-IP-URL rewrite this replaces lost SNI and made Traefik serve its
      # default self-signed certificate.
      def build_conn(coder_url, session_token)
        uri = URI.parse(coder_url)
        public_ip = public_ip_override(uri)

        Faraday.new(url: uri.to_s) do |f|
          f.options.open_timeout = HTTP_TIMEOUTS[:open]
          f.options.timeout      = HTTP_TIMEOUTS[:read]
          f.headers[SESSION_TOKEN_HEADER] = session_token
          f.headers["Accept"] = "application/json"
          f.adapter SniPreservingNetHttp, { ipaddr: public_ip } if public_ip
        end
      end

      # Public-IPv4 override for hosts trusted via either the global
      # URL_SAFETY_TRUSTED_HOSTS or the Coder-specific CODER_TRUSTED_HOSTS
      # list — the same union the Coder integration's URL validation trusts,
      # so one env var governs both the validation and the outbound path.
      # In-cluster names (e.g. the default coder.coder.svc.cluster.local)
      # yield no public IPv4 and fall through to a normal connection.
      def public_ip_override(uri)
        host = uri.host.to_s
        return nil if host.empty?
        return nil unless UrlSafetyValidator.trusted_host?(host, trusted_hosts_override: coder_trusted_hosts)

        UrlSafetyValidator.resolve_public_ipv4(host)
      end

      def coder_trusted_hosts
        Array(Settings.coder&.trusted_hosts).map(&:to_s)
      end
    end
  end
end
