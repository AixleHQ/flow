# frozen_string_literal: true

require "net/http"
require "json"
require "cgi"

module Cursor
  # Cursor::Api — thin HTTP API layer for Cursor's dashboard usage endpoints.
  #
  # Mirrors Codex::Api's split: this layer owns the transport — host, paths, the
  # WorkOS session cookie, request/response shape and JSON parsing — while
  # `Agents::CursorCliAdapter` owns which windows to surface and how to map them
  # onto the usage card. No vendor URL, header or status code leaks past it.
  #
  # The dashboard is authenticated with the same cookie the IDE sends,
  # `WorkosCursorSessionToken=<subject>::<jwt>`. The JWT is the `accessToken` the
  # CLI stores, and `subject` is its `sub` claim — so no extra credential is
  # configured: both halves come from the stored token.
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

    # 401 is the one status with a domain meaning — the stored token has expired
    # and the CLI re-signs in on next use — so it gets its own class.
    class UnauthorizedError < HTTPError; end

    DASHBOARD_ORIGIN = "https://cursor.com"
    USAGE_SUMMARY_URL = "#{DASHBOARD_ORIGIN}/api/usage-summary"
    CURRENT_PERIOD_USAGE_URL = "#{DASHBOARD_ORIGIN}/api/dashboard/get-current-period-usage"

    HTTP_TIMEOUTS = { open: 5, read: 10 }.freeze

    class << self
      # The plan/usage summary the dashboard's usage view shows. This is the
      # primary source for plan windows and the per-model pool split.
      #
      # @param access_token [String] the Cursor access token (a JWT)
      # @return [Hash]
      # @raise [UnauthorizedError] when the token is rejected
      # @raise [ApiError] on any other transport, status or parse failure
      def usage_summary(access_token:)
        json_request(:get, USAGE_SUMMARY_URL, access_token: access_token, op: "usage_summary")
      end

      # The current billing period's usage. A sub-monthly plan (e.g. a weekly
      # Premium seat) reports its allowance here rather than in the summary.
      def current_period_usage(access_token:)
        json_request(:post, CURRENT_PERIOD_USAGE_URL, access_token: access_token, op: "current_period_usage", body: "{}")
      end

      private

      def json_request(method, url, access_token:, op:, body: nil)
        uri = URI(url)
        request = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
        headers(access_token).each { |key, value| request[key] = value }
        request["Content-Type"] = "application/json" if method == :post
        request.body = body if body

        response = Net::HTTP.start(
          uri.hostname, uri.port,
          use_ssl: true,
          open_timeout: HTTP_TIMEOUTS[:open],
          read_timeout: HTTP_TIMEOUTS[:read]
        ) { |http| http.request(request) }

        assert_ok!(response, op: op)
        parse_json(response, op: op)
      rescue Timeout::Error => e
        # Net::OpenTimeout and Net::ReadTimeout both inherit from Timeout::Error.
        raise TimeoutError, e.message
      rescue ApiError
        raise
      rescue StandardError => e
        raise TransportError, e.message
      end

      def headers(access_token)
        {
          "Cookie" => cursor_session_cookie(access_token),
          "Accept" => "application/json",
          "Origin" => DASHBOARD_ORIGIN,
          "Referer" => "#{DASHBOARD_ORIGIN}/dashboard"
        }
      end

      # The cookie Cursor's dashboard sends: `<subject>::<jwt>`, with the subject
      # URL-escaped and the JWT carried raw (its base64url alphabet is cookie-safe).
      def cursor_session_cookie(access_token)
        subject = jwt_subject(access_token)
        "WorkosCursorSessionToken=#{CGI.escape(subject.to_s)}%3A%3A#{access_token}"
      end

      # The unverified `sub` claim of a JWT, or nil when the token is not one.
      def jwt_subject(token)
        segments = token.to_s.split(".")
        return nil unless segments.size == 3

        payload = JSON.parse(Base64.urlsafe_decode64(base64_pad(segments[1])))
        payload.is_a?(Hash) ? payload["sub"] : nil
      rescue StandardError
        nil
      end

      def base64_pad(segment)
        segment + ("=" * ((4 - (segment.length % 4)) % 4))
      end

      def assert_ok!(response, op:)
        return if response.is_a?(Net::HTTPSuccess)

        message = "#{op} failed: HTTP #{response.code}"
        status = response.code.to_i
        raise UnauthorizedError.new(message, status: status, body: response.body.to_s) if status == 401

        raise HTTPError.new(message, status: status, body: response.body.to_s)
      end

      def parse_json(response, op:)
        body = JSON.parse(response.body.to_s)
        raise ParseError, "#{op} failed: expected a JSON object" unless body.is_a?(Hash)

        body
      rescue JSON::ParserError
        raise ParseError, "#{op} failed: invalid JSON response"
      end
    end
  end
end
