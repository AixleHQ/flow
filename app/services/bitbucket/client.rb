# frozen_string_literal: true

module Bitbucket
  # REST 2.0 client for one credential.
  #
  # The host is fixed and every path segment is encoded on its own, so a
  # workspace, slug or `{uuid}` from a caller cannot add a path separator or a
  # query. Pagination follows only the `page` parameter of Bitbucket's `next`
  # link, re-asked on our own path: no provider-supplied URL is ever fetched.
  class Client
    MAX_RETRIES = 2
    BASE_PATH = "/2.0"

    Redirected = Data.define(:path)
    Response = Data.define(:status, :body, :headers)

    attr_reader :credential

    def initialize(credential:, logger: Rails.logger, sleeper: ->(seconds) { sleep(seconds) })
      @credential = credential
      @logger = logger
      @sleeper = sleeper
    end

    def get(*segments, params: {}) = request(:get, segments, params: params)

    def post(*segments, body: nil, params: {}, raw: false)
      request(:post, segments, params: params, body: body, raw: raw)
    end

    def put(*segments, body:, params: {}) = request(:put, segments, params: params, body: body)

    # Not `delete`, so it cannot be reached by a caller that meant Object#delete.
    def request_delete(*segments, params: {}) = request(:delete, segments, params: params)

    # One page and the cursor of the next one (nil on the last page). The cursor
    # is the `page` value Bitbucket put in its `next` link — a number on most
    # endpoints, an opaque token on some.
    def page(*segments, params: {}, cursor: nil)
      body = get(*segments, params: cursor.present? ? params.merge(page: cursor) : params)
      [ Array(body["values"]), next_cursor(body) ]
    end

    # Every value across pages, bounded by `limit` and `max_pages`; the second
    # element says whether more were left behind.
    def paginate(*segments, params: {}, limit: 1000, max_pages: 20)
      values = []
      cursor = nil
      max_pages.times do
        items, cursor = page(*segments, params: params, cursor: cursor)
        values.concat(items)
        break if cursor.nil? || values.size >= limit
      end
      [ values.first(limit), values.size > limit || cursor.present? ]
    end

    private

    def request(method, segments, params:, body: nil, raw: false, attempt: 0)
      path = build_path(segments)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = connection.run_request(method, path, body&.to_json, headers(body)) do |req|
        req.params.update(params.compact.transform_keys(&:to_s))
      end
      log(method, path, response, started)

      case response.status
      when 200..299
        raw ? Response.new(status: response.status, body: parse(response), headers: response.headers.to_h) : parse(response)
      when 301, 302, 303, 307, 308 then follow_redirect(response, method, raw, attempt)
      when 401 then retry_unauthorized(method, segments, params, body, raw, attempt)
      when 403 then raise Error::PermissionDenied, message_of(response, "Bitbucket denied this operation")
      when 404 then raise Error::NotFound
      when 409 then raise Error::Conflict, message_of(response)
      when 429 then retry_throttled(response, method, segments, params, body, raw, attempt)
      when 400, 422 then raise Error::ValidationFailed.new(message_of(response), details: fields_of(response))
      when 500..599 then retry_server_error(response, method, segments, params, body, raw, attempt)
      else raise Error.new(message_of(response), code: "provider_error", status: response.status)
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      # The transport cannot say whether a write landed, and calling one that
      # did "failed" is how duplicates get made.
      raise Error::OutcomeUnknown, "Bitbucket did not answer (#{e.class.name.demodulize})" unless method == :get

      raise Error.new("Bitbucket could not be reached (#{e.class.name.demodulize})", code: "timeout")
    end

    # Bitbucket answers some reads with a redirect to another path on its own API
    # host — a pull request's diffstat and diff do. Such a read is followed; a
    # redirect anywhere else is refused, because the request carries the token.
    def follow_redirect(response, method, raw, attempt)
      location = URI.parse(response.headers["location"].to_s)
      on_api = "#{location.scheme}://#{location.host}" == AppConfig::API_HOST && location.path.start_with?("#{BASE_PATH}/")
      unless method == :get && on_api && attempt < MAX_RETRIES
        raise Error.new("Bitbucket redirected this request away from its API", code: "provider_error", status: response.status)
      end

      request(:get, Redirected.new(path: location.path), params: Rack::Utils.parse_query(location.query.to_s),
                                                         raw: raw, attempt: attempt + 1)
    rescue URI::InvalidURIError
      raise Error.new("Bitbucket redirected this request to an unreadable address", code: "provider_error", status: response.status)
    end

    # One retry, and only with a different credential: a second 401 is Bitbucket
    # refusing the identity, not the token.
    def retry_unauthorized(method, segments, params, body, raw, attempt)
      fresh = credential.refresh if attempt.zero?
      raise Error::NotAuthorized, "Bitbucket rejected this connection's credential" unless fresh

      @credential = fresh
      request(method, segments, params: params, body: body, raw: raw, attempt: attempt + 1)
    end

    def retry_throttled(response, method, segments, params, body, raw, attempt)
      retry_after = response.headers["retry-after"].to_f
      if method != :get || attempt >= MAX_RETRIES
        raise Error::RateLimited.new("Bitbucket is rate-limiting this connection", retry_after: retry_after.positive? ? retry_after : nil)
      end

      @sleeper.call(retry_after.clamp(0.5, 30))
      request(method, segments, params: params, body: body, raw: raw, attempt: attempt + 1)
    end

    # Only a read is retried: a write that got a 5xx may have been applied.
    def retry_server_error(response, method, segments, params, body, raw, attempt)
      raise Error::OutcomeUnknown, "Bitbucket returned #{response.status} on a write" unless method == :get
      raise Error.new("Bitbucket returned #{response.status}", code: "provider_error", status: response.status) if attempt >= MAX_RETRIES

      @sleeper.call((0.3 * (2**attempt)) + rand(0.0..0.2))
      request(method, segments, params: params, body: body, raw: raw, attempt: attempt + 1)
    end

    def build_path(segments)
      return segments.path if segments.is_a?(Redirected)

      parts = Array(segments).flatten.compact.map { |segment| ERB::Util.url_encode(segment.to_s) }
      raise ArgumentError, "a Bitbucket path needs at least one segment" if parts.empty?

      "#{BASE_PATH}/#{parts.join('/')}"
    end

    def headers(body)
      headers = { "Accept" => "application/json" }
      headers["Content-Type"] = "application/json" if body
      headers.merge(credential.authorization_headers)
    end

    def parse(response)
      return {} if response.body.blank?

      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      raise Error.new("Bitbucket returned a non-JSON body", code: "provider_error", status: response.status)
    end

    def next_cursor(body)
      link = body["next"].presence or return
      Rack::Utils.parse_query(URI.parse(link).query.to_s)["page"].presence
    rescue URI::InvalidURIError
      nil
    end

    # Bitbucket's envelope: {"type": "error", "error": {"message", "detail", "fields"}}.
    # Trimmed, because provider text reaches agent context and the browser.
    def message_of(response, fallback = nil)
      error = error_of(response)
      text = [ error["message"], error["detail"] ].compact_blank.uniq.join(": ")
      text.presence&.truncate(500) || fallback || "Bitbucket returned #{response.status}"
    end

    def fields_of(response) = error_of(response)["fields"].presence

    def error_of(response)
      body = JSON.parse(response.body.to_s)
      body.is_a?(Hash) && body["error"].is_a?(Hash) ? body["error"] : {}
    rescue JSON::ParserError
      {}
    end

    def connection
      @connection ||= Faraday.new(url: AppConfig::API_HOST) do |f|
        f.options.open_timeout = AppConfig.open_timeout
        f.options.timeout = AppConfig.read_timeout
        # Bitbucket repeats a parameter for several values (`state=OPEN&state=MERGED`)
        # and ignores Rails' `state[]=` form.
        f.options.params_encoder = Faraday::FlatParamsEncoder
        # No redirect middleware: a followed redirect would resend the token to
        # whatever host Bitbucket named.
        f.adapter Faraday.default_adapter
      end
    end

    def log(method, path, response, started)
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      @logger.info("[Bitbucket::Client] #{method.to_s.upcase} #{path} status=#{response.status} ms=#{ms} " \
                   "request_id=#{response.headers['x-request-id']}")
    end
  end
end
