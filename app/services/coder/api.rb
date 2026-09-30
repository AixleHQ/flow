# frozen_string_literal: true

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
  #   │   └── UnsafeUrlError — the host has no address we may dial
  #   ├── TimeoutError   — open/read timeout
  #   └── ParseError     — invalid JSON in a response body
  class Api
    class ApiError < StandardError; end
    class TransportError < ApiError; end
    class UnsafeUrlError < TransportError; end
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

    class << self
      def verify_token(coder_url:, session_token:)
        body = json_get("/api/v2/users/me", coder_url: coder_url, session_token: session_token, op: "verify_token")
        { id: body["id"], username: body["username"], email: body["email"] }
      end

      # `query` is Coder's workspace search, e.g. "owner:me".
      def list_workspaces(coder_url:, session_token:, query: nil)
        path = query.present? ? "/api/v2/workspaces?q=#{CGI.escape(query)}" : "/api/v2/workspaces"
        body = json_get(path, coder_url: coder_url, session_token: session_token, op: "list_workspaces")
        body["workspaces"] || []
      end

      def build_workspace(coder_url:, session_token:, workspace_id:, transition:, orphan: false)
        body = { transition: transition }
        body[:orphan] = true if orphan
        json_post(
          "/api/v2/workspaces/#{workspace_id}/builds",
          body,
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

      # Raises like every other call here. Collapsing failures to `[]` made an
      # expired token or a 403 indistinguishable from "the template isn't
      # there", and callers reported the latter.
      def list_templates(coder_url:, session_token:)
        Array(json_get("/api/v2/templates", coder_url: coder_url, session_token: session_token, op: "list_templates"))
      end

      def create_workspace(coder_url:, session_token:, user_id:, name:, template_id:)
        json_post(
          "/api/v2/users/#{user_id}/workspaces",
          { name: name, template_id: template_id },
          coder_url: coder_url, session_token: session_token,
          op: "create_workspace", accept: [ 200, 201 ]
        )
      end

      # Where a request to `uri` is dialed.
      # Trusted host  → nil: resolved by the system (internal) resolver, for our
      #                 own hosts that only resolve privately inside the cluster.
      # Non-trusted host → its public IPv4 from public DNS, or a refusal. Never
      #                 the system resolver: its answer can differ from the one
      #                 checked when the URL was saved.
      def dial_address(uri)
        trusted = UrlSafetyValidator.configured_trusted_hosts
        return nil if UrlSafetyValidator.trusted_host?(uri.host.to_s, trusted_hosts_override: trusted)

        public_address(uri)
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

      # The socket goes to the address `dial_address` chose while the URL keeps
      # the hostname, so the Host header, SNI and certificate check are the
      # Coder instance's own.
      def build_conn(coder_url, session_token)
        ip = dial_address(URI.parse(coder_url))

        Faraday.new(url: coder_url) do |f|
          f.options.open_timeout = HTTP_TIMEOUTS[:open]
          f.options.timeout      = HTTP_TIMEOUTS[:read]
          f.headers[SESSION_TOKEN_HEADER] = session_token
          f.headers["Accept"] = "application/json"
          f.adapter(:net_http) { |http| http.ipaddr = ip if ip }
        end
      rescue URI::InvalidURIError
        raise UnsafeUrlError, "Coder URL is not a valid URL"
      end

      def public_address(uri)
        host = uri.host.to_s.downcase
        raise UnsafeUrlError, "Coder URL must use http or https" unless %w[http https].include?(uri.scheme)
        raise UnsafeUrlError, "Coder URL cannot point to internal services" if host.empty? || UrlSafetyValidator::BLOCKED_HOSTS.include?(host)

        literal = UrlSafetyValidator.ip_or_nil(host)
        if literal
          raise UnsafeUrlError, "Coder URL cannot point to a private or internal address" if UrlSafetyValidator.blocked_ip?(literal)

          return literal.to_s
        end

        UrlSafetyValidator.resolve_public_ipv4(host) ||
          raise(UnsafeUrlError, "Coder host #{host} has no public address")
      end
    end
  end
end
