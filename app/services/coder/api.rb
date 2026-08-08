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

      # Build the Faraday connection. The DNS path is chosen by the
      # trusted-host check (see `resolve_target`): a trusted host is resolved
      # normally through the system (internal) resolver, while a non-trusted
      # host must not be resolved internally — it is looked up via public DNS
      # and connected to by its public IP directly, preserving the original
      # hostname for the Host header and TLS SNI.
      def build_conn(coder_url, session_token)
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

      # Trusted host  → resolve normally (internal DNS allowed): return the
      #                 URL unchanged so the system resolver is used.
      # Non-trusted host → must not use internal DNS: resolve via public DNS
      #                 and connect to the public IPv4 directly.
      def resolve_target(uri)
        return [ uri.to_s, nil, nil ] if UrlSafetyValidator.trusted_host?(uri.host.to_s)

        public_ip = UrlSafetyValidator.resolve_public_ipv4(uri.host)
        return [ uri.to_s, nil, nil ] if public_ip.nil?

        rewritten = uri.dup
        rewritten.host = public_ip

        port = uri.port
        host_header = port == uri.default_port ? uri.host : "#{uri.host}:#{port}"
        [ rewritten.to_s, uri.host, host_header ]
      end
    end
  end
end
