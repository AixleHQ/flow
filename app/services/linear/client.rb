# frozen_string_literal: true

module Linear
  # GraphQL client for api.linear.app, failing with Trackers::Error. Linear
  # reports most failures in the body's `errors` — on a 200 or a 400 — and its
  # `extensions.type` is the stable part. Only a read is retried: a write that
  # failed on the server may still have landed.
  class Client
    MAX_RETRIES = 2

    def initialize(credential:, retry_delay: 0.3, logger: Rails.logger)
      @credential = credential
      @retry_delay = retry_delay
      @logger = logger
    end

    def query(document, variables = {}) = request(document, variables, write: false)
    def mutate(document, variables = {}) = request(document, variables, write: true)

    private

    def request(document, variables, write:, attempt: 0)
      response = connection.post("/graphql", { query: document, variables: variables.compact }.to_json, headers)
      log(response)
      body = parse(response)
      errors = Array(body["errors"])
      return body["data"].to_h if response.success? && errors.empty?

      error = error_for(response, errors)
      case error.code
      when "not_authorized" then unauthorized(document, variables, write, attempt)
      when "provider_error" then server_error(error, document, variables, write, attempt)
      else raise error
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise Trackers::Error::OutcomeUnknown, "Linear did not answer (#{e.class})" if write

      raise Trackers::Error.new("Linear did not answer (#{e.class})", code: "timeout")
    end

    def unauthorized(document, variables, write, attempt)
      raise Trackers::Error.new("Linear rejected this connection's credential", code: "not_authorized") if attempt.positive?

      @credential.invalidate!
      request(document, variables, write: write, attempt: attempt + 1)
    end

    def server_error(error, document, variables, write, attempt)
      raise Trackers::Error::OutcomeUnknown, "#{error.message} on a write" if write
      raise error if attempt >= MAX_RETRIES

      sleep(@retry_delay * (2**attempt))
      request(document, variables, write: write, attempt: attempt + 1)
    end

    def error_for(response, errors)
      first = errors.first.to_h
      extensions = first["extensions"].to_h
      type = extensions["type"].to_s.downcase
      message = (extensions["userPresentableMessage"].presence || first["message"].presence ||
                 "Linear returned #{response.status}").to_s.truncate(300)
      Trackers::Error.new(message, code: code_for(response, extensions["code"].to_s.upcase, type, message, errors))
    end

    def code_for(response, code, type, message, errors)
      if response.status == 429 || code == "RATELIMITED" || type == "ratelimited" then "rate_limited"
      elsif response.status == 401 || type.include?("authentication") then "not_authorized"
      elsif response.status == 403 || type == "forbidden" || type.include?("not accessible") then "permission_denied"
      elsif message.match?(/not found|could not find|does not exist/i) then "not_found"
      elsif response.status >= 500 || (errors.empty? && !response.success?) then "provider_error"
      else "validation_failed"
      end
    end

    def headers
      { "Content-Type" => "application/json", "Accept" => "application/json" }.merge(@credential.authorization_headers)
    end

    def parse(response)
      response.body.present? ? JSON.parse(response.body) : {}
    rescue JSON::ParserError
      response.success? ? raise(Trackers::Error.new("Linear returned a non-JSON body", code: "provider_error")) : {}
    end

    def connection
      @connection ||= Faraday.new(url: AppConfig::API_HOST) do |f|
        f.options.open_timeout = AppConfig.open_timeout
        f.options.timeout = AppConfig.read_timeout
        # No redirect middleware: a followed redirect would resend the credential.
        f.adapter Faraday.default_adapter
      end
    end

    def log(response)
      @logger.info("[Linear::Client] POST /graphql status=#{response.status} " \
                   "complexity=#{response.headers['x-complexity']} remaining=#{response.headers['x-ratelimit-requests-remaining']}")
    end
  end
end
