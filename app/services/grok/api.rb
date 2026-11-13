# frozen_string_literal: true

require "net/http"
require "json"

module Grok
  # Grok::Api — thin HTTP API layer for xAI's Grok CLI billing endpoint.
  #
  # Mirrors Codex::Api's split: this layer owns the transport — host, path, the
  # CLI-only auth header, request/response shape and JSON parsing — while
  # `Agents::GrokAdapter` owns which windows to surface. No vendor URL, header
  # or status code leaks past it.
  #
  # The endpoint is the CLI's own inference proxy; it answers only for a signed-in
  # (OAuth) session, which is why an API-key login has no windows to read.
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

    class UnauthorizedError < HTTPError; end

    BILLING_URL = "https://cli-chat-proxy.grok.com/v1/billing"

    # xAI gates this endpoint to the CLI's own client; the header is what the CLI
    # sends and the server checks before it returns credit usage.
    GROK_CLI_AUTH_HEADER = "xai-grok-cli"

    HTTP_TIMEOUTS = { open: 5, read: 10 }.freeze

    class << self
      # The billing/credit view the CLI reads for its own usage display.
      #
      # @param access_token [String] the OAuth session token
      # @param user_id [String, nil] the account's user id, when the entry carries one
      # @return [Hash]
      # @raise [UnauthorizedError] when the token is rejected
      # @raise [ApiError] on any other transport, status or parse failure
      def billing(access_token:, user_id: nil)
        uri = URI(BILLING_URL)
        uri.query = URI.encode_www_form(format: "credits")
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["X-XAI-Token-Auth"] = GROK_CLI_AUTH_HEADER
        request["Accept"] = "application/json"
        request["x-userid"] = user_id if user_id.present?

        response = Net::HTTP.start(
          uri.hostname, uri.port,
          use_ssl: true,
          open_timeout: HTTP_TIMEOUTS[:open],
          read_timeout: HTTP_TIMEOUTS[:read]
        ) { |http| http.request(request) }

        assert_ok!(response, op: "billing")
        parse_json(response, op: "billing")
      rescue Timeout::Error => e
        raise TimeoutError, e.message
      rescue ApiError
        raise
      rescue StandardError => e
        raise TransportError, e.message
      end

      private

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
