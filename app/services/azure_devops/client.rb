# frozen_string_literal: true

module AzureDevops
  # REST client for one resolved connection.
  #
  # Everything that could be attacker-influenced is constrained here rather than
  # at each call site: the host is fixed, every path component is encoded
  # separately, the api-version is chosen per endpoint family, and no
  # provider-supplied URL is ever fetched. Callers pass path SEGMENTS, never a
  # path string.
  class Client
    # A single global api-version does not exist for this API. Git and Work Item
    # cores are GA at 7.1; work item comments are still only published under a
    # preview version. Appending one number to everything silently 404s or, worse,
    # silently returns a differently-shaped body.
    API_VERSIONS = {
      default: "7.1",
      git: "7.1",
      wit: "7.1",
      # Comments have never left preview. The revision suffix is part of the
      # contract — dropping it does not fall back to GA, it fails.
      wit_comments: "7.1-preview.4",
      core: "7.1",
      build: "7.1",
      policy: "7.1"
    }.freeze

    MAX_RETRIES = 2

    def initialize(credential:, organization:, logger: Rails.logger)
      @credential = credential
      @organization = organization
      @logger = logger
    end

    attr_reader :credential, :organization

    def get(*segments, params: {}, family: :default, project: nil)
      request(:get, segments, params: params, family: family, project: project)
    end

    def post(*segments, body:, params: {}, family: :default, project: nil, content_type: "application/json")
      request(:post, segments, params: params, family: family, project: project,
                               body: body, content_type: content_type)
    end

    def patch(*segments, body:, params: {}, family: :default, project: nil, content_type: "application/json")
      request(:patch, segments, params: params, family: family, project: project,
                                body: body, content_type: content_type)
    end

    # Follows Azure's `x-ms-continuationtoken` header across pages, bounded by
    # `max_pages` and `limit`. The continuation token is a provider value echoed
    # back as a query parameter — no provider-supplied URL is ever fetched.
    def paginate(*segments, params: {}, family: :default, project: nil, limit: 100, max_pages: 10, key: "value")
      out = []
      token = nil
      max_pages.times do
        page_params = params.dup
        page_params[:continuationToken] = token if token.present?
        response = request(:get, segments, params: page_params, family: family, project: project, raw: true)

        out.concat(Array(parse_body(response)[key]))
        token = response.headers["x-ms-continuationtoken"].presence
        break if token.blank? || out.size >= limit
      end

      [ out.first(limit), out.size > limit || token.present? ]
    end

    private

    def request(method, segments, params:, family:, project:, body: nil, content_type: nil, raw: false, attempt: 0)
      url = build_url(segments, project: project)
      query = params.compact.merge("api-version" => API_VERSIONS.fetch(family, API_VERSIONS[:default]))

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = connection.run_request(method, url, serialize(body, content_type), request_headers(content_type)) do |req|
        req.params.update(query.transform_keys(&:to_s))
      end
      log(method, url, response, started)

      case response.status
      when 200..299 then raw ? response : parse_body(response)
      when 401 then handle_unauthorized(method, segments, params, family, project, body, content_type, raw, attempt)
      when 403 then raise PermissionDenied, "Azure denied this operation"
      when 404 then raise NotFound, "Azure has no such resource, or this identity cannot see it"
      when 409 then raise Conflict, azure_message(response)
      when 429 then handle_throttled(response, method, segments, params, family, project, body, content_type, raw, attempt)
      when 400, 422 then raise ValidationFailed.new(azure_message(response), details: azure_details(response))
      when 500..599 then retry_or_raise(response, method, segments, params, family, project, body, content_type, raw, attempt)
      else raise Error.new(azure_message(response), code: "azure_error", status: response.status)
      end
    rescue Faraday::TimeoutError
      # For a read this is just a timeout. For a write the request may well have
      # landed, and calling it "failed" is how duplicate pull requests get made.
      raise OutcomeUnknown, "Azure did not answer in time" unless method == :get

      raise Error.new("Azure request timed out", code: "timeout")
    end

    # Exactly one reacquisition and one retry. The token provider authenticates
    # the app; a second 401 means Azure is refusing the identity, not the token.
    def handle_unauthorized(method, segments, params, family, project, body, content_type, raw, attempt)
      raise NotAuthorized, "Azure rejected the credential for this connection" if attempt.positive?

      credential.invalidate!
      request(method, segments, params: params, family: family, project: project,
                                body: body, content_type: content_type, raw: raw, attempt: attempt + 1)
    end

    # Azure publishes a delay rather than a fixed requests-per-minute quota, and
    # can attach one to a SUCCESSFUL response too. Only the 429 is retried here;
    # a successful write carrying Retry-After must never be replayed.
    def handle_throttled(response, method, segments, params, family, project, body, content_type, raw, attempt)
      retry_after = response.headers["retry-after"].to_f
      raise RateLimited.new("Azure is throttling this connection", retry_after: retry_after) if attempt >= MAX_RETRIES
      raise RateLimited.new("Azure is throttling this connection", retry_after: retry_after) unless method == :get

      sleep([ retry_after, 30 ].min.clamp(0.5, 30))
      request(method, segments, params: params, family: family, project: project,
                                body: body, content_type: content_type, raw: raw, attempt: attempt + 1)
    end

    # Only safe (GET) requests are retried on a 5xx. A POST that got a 500 may
    # have been applied.
    def retry_or_raise(response, method, segments, params, family, project, body, content_type, raw, attempt)
      raise OutcomeUnknown, "Azure returned #{response.status} on a write" if method != :get
      raise Error.new("Azure returned #{response.status}", code: "provider_error", status: response.status) if attempt >= MAX_RETRIES

      sleep((0.3 * (2**attempt)) + rand(0.0..0.2))
      request(method, segments, params: params, family: family, project: project,
                                body: body, content_type: content_type, raw: raw, attempt: attempt + 1)
    end

    # Every segment is encoded on its own, so an Azure project literally named
    # "A/B" or "Customer Platform" cannot inject a path separator, and no caller
    # can smuggle `..` or a query string through an identifier.
    def build_url(segments, project:)
      parts = [ ERB::Util.url_encode(organization) ]
      parts << ERB::Util.url_encode(project.to_s) if project.present?
      parts.concat(Array(segments).flatten.compact.map { |s| ERB::Util.url_encode(s.to_s) })
      "/#{parts.join('/')}"
    end

    def request_headers(content_type)
      headers = { "Accept" => "application/json" }
      headers["Content-Type"] = content_type if content_type
      headers.merge(credential.authorization_headers)
    end

    def serialize(body, content_type)
      return nil if body.nil?
      return body if body.is_a?(String)

      content_type.to_s.include?("json") ? body.to_json : body
    end

    def parse_body(response)
      return {} if response.body.blank?

      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      raise Error.new("Azure returned a non-JSON body", code: "provider_error", status: response.status)
    end

    # Azure's error envelope. Returned verbatim only after being trimmed to one
    # line — provider messages reach agent context and the browser.
    def azure_message(response)
      body = begin
        JSON.parse(response.body.to_s)
      rescue StandardError
        {}
      end
      body["message"].presence&.to_s&.truncate(500) || "Azure returned #{response.status}"
    end

    def azure_details(response)
      body = begin
        JSON.parse(response.body.to_s)
      rescue StandardError
        {}
      end
      body["typeKey"].presence
    end

    def connection
      @connection ||= Faraday.new(url: AppConfig.api_host) do |f|
        f.options.open_timeout = AppConfig.open_timeout
        f.options.timeout = AppConfig.read_timeout
        # No redirect middleware on purpose: a followed redirect would resend the
        # Authorization header to whatever host Azure named.
        f.adapter Faraday.default_adapter
      end
    end

    # Endpoint family, status, duration and Azure's own request id — never the
    # Authorization header, never the body.
    def log(method, url, response, started)
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      @logger.info(
        "[AzureDevops::Client] #{method.to_s.upcase} #{url.split('?').first} " \
        "status=#{response.status} ms=#{ms} request_id=#{response.headers['x-vss-e2eid']}"
      )
    end
  end
end
