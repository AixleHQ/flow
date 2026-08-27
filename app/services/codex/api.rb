# frozen_string_literal: true

module Codex
  # Codex::Api — thin HTTP API layer for the OpenAI Codex backend.
  #
  # Class methods receive the credential material (`access_token`,
  # `refresh_token`) explicitly. `Agents::CodexAdapter` owns the domain logic —
  # which models to offer, when a rejected token is worth refreshing, how the
  # migration map turns into config.toml — while this layer owns the transport:
  # hosts, endpoint paths, the client-version gate, request/response shape and
  # JSON parsing. No vendor URL, header or status code leaks past it.
  #
  # Errors collapse into a small hierarchy so callers can rescue once:
  #
  #   ApiError
  #   ├── HTTPError         — non-success HTTP status (`.status` populated)
  #   │   └── UnauthorizedError — 401; the access token needs refreshing
  #   ├── TransportError    — Faraday-level error (connection/SSL/etc.)
  #   ├── TimeoutError      — open/read timeout
  #   └── ParseError        — invalid JSON in a response body
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

    # 401 is the one status with a domain meaning — the caller holds a refresh
    # token and can retry — so it gets its own class instead of making callers
    # match on `.status`.
    class UnauthorizedError < HTTPError; end

    MODELS_URL = "https://chatgpt.com/backend-api/codex/models"
    # Codex model discovery lives under `/codex`, but the subscription quota
    # endpoint used by the CLI's `/status` view lives under `/wham`.
    USAGE_URL = "https://chatgpt.com/backend-api/wham/usage"
    OAUTH_TOKEN_URL = "https://auth.openai.com/oauth/token"
    OAUTH_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"

    # `client_version` gates the catalog: each model carries a
    # `minimal_client_version` and the endpoint hides the models a client that old
    # cannot run (the gpt-5.6 family needs >= 0.144.0). Keep this at the Codex CLI
    # version baked into docker/codex/Dockerfile, or the model picker and the
    # migration map both go stale against the CLI the session actually runs.
    CLIENT_VERSION = "0.147.0"

    HTTP_TIMEOUTS = { open: 5, read: 10 }.freeze

    # One catalog entry. `upgrade_target` is the slug the CLI migrates this model
    # to, and its presence is what arms the startup model-migration dialog
    # (codex-rs/tui/src/app/startup_prompts.rs).
    Model = Struct.new(:slug, :display_name, :description, :visibility, :upgrade_target, keyword_init: true) do
      def listed?
        visibility == "list"
      end

      def upgradable?
        slug.present? && upgrade_target.present?
      end
    end

    # An OAuth token response. `refresh_token` / `id_token` are nil when the
    # server rotates only the access token; deciding what to keep is the caller's
    # business, not the transport's.
    Tokens = Struct.new(:access_token, :refresh_token, :id_token, keyword_init: true)

    class << self
      # The full model catalog, including models hidden from the picker — a
      # session pinned to an older model is exactly the case that needs its
      # upgrade target.
      #
      # @param access_token [String]
      # @return [Array<Model>]
      # @raise [UnauthorizedError] when the access token is rejected
      # @raise [ApiError] on any other transport, status or parse failure
      def models(access_token:)
        body = json_get(
          MODELS_URL,
          params: { client_version: CLIENT_VERSION },
          headers: { "Authorization" => "Bearer #{access_token}" },
          op: "models"
        )

        Array(body["models"]).filter_map { |raw| build_model(raw) }
      end

      # The same subscription limits shown by Codex's `/status` view.
      def usage(access_token:, account_id: nil)
        headers = { "Authorization" => "Bearer #{access_token}" }
        headers["ChatGPT-Account-Id"] = account_id if account_id.present?
        json_get(USAGE_URL, params: {}, headers:, op: "usage")
      end

      # Exchange a refresh token for a fresh access token.
      #
      # @param refresh_token [String]
      # @return [Tokens]
      # @raise [UnauthorizedError] when the refresh token is rejected
      # @raise [ApiError] on any other transport, status or parse failure
      def refresh_tokens(refresh_token:)
        body = form_post(
          OAUTH_TOKEN_URL,
          {
            grant_type: "refresh_token",
            client_id: OAUTH_CLIENT_ID,
            refresh_token: refresh_token
          },
          op: "refresh_tokens"
        )

        Tokens.new(
          access_token: body["access_token"],
          refresh_token: body["refresh_token"],
          id_token: body["id_token"]
        )
      end

      private

      def build_model(raw)
        return nil unless raw.is_a?(Hash)

        Model.new(
          slug: raw["slug"],
          display_name: raw["display_name"].presence || raw["slug"],
          description: raw["description"].to_s,
          visibility: raw["visibility"],
          upgrade_target: raw.dig("upgrade", "model")
        )
      end

      def json_get(url, params:, headers:, op:)
        response = request(:get, url, headers: headers) { |req| req.params.update(params) }
        assert_ok!(response, op: op)
        parse_json(response, op: op)
      end

      def form_post(url, form, op:)
        response = request(:post, url, headers: { "Content-Type" => "application/x-www-form-urlencoded" }) do |req|
          req.body = URI.encode_www_form(form)
        end
        assert_ok!(response, op: op)
        parse_json(response, op: op)
      end

      def request(method, url, headers:, &block)
        build_conn(headers).public_send(method, url, &block)
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

      def build_conn(headers)
        Faraday.new do |f|
          f.options.open_timeout = HTTP_TIMEOUTS[:open]
          f.options.timeout      = HTTP_TIMEOUTS[:read]
          f.headers["Accept"] = "application/json"
          headers.each { |key, value| f.headers[key] = value }
        end
      end

      def assert_ok!(response, op:)
        return if response.success?

        message = "#{op} failed: HTTP #{response.status}"
        body = response.body.to_s
        raise UnauthorizedError.new(message, status: response.status, body: body) if response.status == 401

        raise HTTPError.new(message, status: response.status, body: body)
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
