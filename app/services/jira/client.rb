# frozen_string_literal: true

module Jira
  # REST client for one site, through Atlassian's gateway
  # (api.atlassian.com/ex/jira/{cloud id}) — the only host either auth mode's
  # token is good for, so a site URL someone typed is never sent a token.
  #
  # Callers pass path SEGMENTS, each encoded on its own, so an issue key or a
  # user-supplied id cannot add a path separator or a query string.
  class Client
    MAX_RETRIES = 2
    MAX_THROTTLE_WAIT = 10

    def initialize(cloud_id:, credential:, retry_delay: 0.3, logger: Rails.logger)
      raise Error.new("This connection has no Jira site", code: "not_configured") if cloud_id.blank?

      @cloud_id = cloud_id
      @credential = credential
      @retry_delay = retry_delay
      @logger = logger
    end

    def get(*segments, params: {}) = request(:get, segments, params: params)
    def post(*segments, body:, params: {}) = request(:post, segments, params: params, body: body)
    def put(*segments, body:, params: {}) = request(:put, segments, params: params, body: body)

    # Not `delete`, so it cannot be reached by a caller that meant Object#delete.
    def request_delete(*segments, body: nil, params: {}) = request(:delete, segments, params: params, body: body)

    private

    def request(method, segments, params:, body: nil, attempt: 0)
      path = build_path(segments)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = connection.run_request(method, path, body&.to_json, headers(body)) do |req|
        req.params.update(params.compact.transform_keys(&:to_s))
      end
      log(method, path, response, started)

      case response.status
      when 200..299 then parse(response)
      when 401 then unauthorized(method, segments, params, body, attempt)
      when 403 then raise Error.new(message(response, "Jira denied this operation"), code: "permission_denied", status: 403)
      when 404
        raise Error.new(message(response, "Jira has no such resource, or this connection cannot see it"), code: "not_found", status: 404)
      when 409 then raise Error.new(message(response), code: "conflict", status: 409)
      when 400, 422
        raise Error.new(message(response), code: "validation_failed", status: response.status, details: field_errors(response))
      when 429 then throttled(response, method, segments, params, body, attempt)
      when 500..599 then server_error(response, method, segments, params, body, attempt)
      else raise Error.new(message(response), code: "provider_error", status: response.status)
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      # The transport cannot say which side of "sent" a write failed on, and
      # calling a write failed when it landed is how duplicates get filed.
      raise Error::OutcomeUnknown, "Jira did not answer (#{e.class})" unless method == :get

      raise Error.new("Jira did not answer (#{e.class})", code: "timeout")
    end

    def unauthorized(method, segments, params, body, attempt)
      raise Error.new("Jira rejected this connection's credential", code: "not_authorized", status: 401) if attempt.positive?

      @credential.invalidate!
      request(method, segments, params: params, body: body, attempt: attempt + 1)
    end

    # Only a read is retried: a write that was throttled may still have landed.
    def throttled(response, method, segments, params, body, attempt)
      wait = response.headers["retry-after"].to_f
      if method != :get || attempt >= MAX_RETRIES || wait > MAX_THROTTLE_WAIT
        raise Error.new("Jira is rate limiting this connection", code: "rate_limited", status: 429,
                                                                  details: { retry_after: wait })
      end

      sleep(wait)
      request(method, segments, params: params, body: body, attempt: attempt + 1)
    end

    def server_error(response, method, segments, params, body, attempt)
      raise Error::OutcomeUnknown, "Jira returned #{response.status} on a write" if method != :get
      raise Error.new("Jira returned #{response.status}", code: "provider_error", status: response.status) if attempt >= MAX_RETRIES

      sleep(@retry_delay * (2**attempt))
      request(method, segments, params: params, body: body, attempt: attempt + 1)
    end

    def build_path(segments)
      parts = [ "ex", "jira", @cloud_id, "rest" ] + Array(segments).flatten.compact
      "/#{parts.map { |s| ERB::Util.url_encode(s.to_s) }.join('/')}"
    end

    def headers(body)
      base = { "Accept" => "application/json" }
      base["Content-Type"] = "application/json" if body
      base.merge(@credential.authorization_headers)
    end

    def parse(response)
      return {} if response.body.blank?

      JSON.parse(response.body)
    rescue JSON::ParserError
      raise Error.new("Jira returned a non-JSON body", code: "provider_error", status: response.status)
    end

    # Jira's error envelope, trimmed: provider messages reach agents and the browser.
    def message(response, fallback = nil)
      body = error_body(response)
      text = [ *Array(body["errorMessages"]), *body["errors"].to_h.map { |field, error| "#{field}: #{error}" } ].join("; ")
      text.presence&.truncate(500) || fallback || "Jira returned #{response.status}"
    end

    def field_errors(response)
      error_body(response)["errors"].presence
    end

    def error_body(response)
      body = JSON.parse(response.body.to_s)
      body.is_a?(Hash) ? body : {}
    rescue JSON::ParserError
      {}
    end

    def connection
      @connection ||= Faraday.new(url: AppConfig::API_HOST) do |f|
        f.options.open_timeout = AppConfig.open_timeout
        f.options.timeout = AppConfig.read_timeout
        # No redirect middleware: a followed redirect would resend the token.
        f.adapter Faraday.default_adapter
      end
    end

    def log(method, path, response, started)
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      @logger.info("[Jira::Client] #{method.to_s.upcase} #{path} status=#{response.status} ms=#{ms} " \
                   "request_id=#{response.headers['atl-traceid']}")
    end
  end
end
