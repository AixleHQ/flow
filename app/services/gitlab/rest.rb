# frozen_string_literal: true

module Gitlab
  # JSON client for GitLab's REST API (v4), failing with Trackers::Error — the
  # tracker, the service-account setup and the OAuth connect flow use it; the
  # code host still goes through the gitlab gem (Gitlab::TokenService).
  #
  # The host is the deployment's (GITLAB_ENDPOINT), never one a request names.
  # Callers pass paths whose ids they encoded. Only a read is retried: a write
  # that failed on the server may have landed.
  class Rest
    MAX_RETRIES = 2
    MAX_PAGES = 10

    def self.for(integration)
      new(token: integration.credentials_data["personal_access_token"])
    end

    def initialize(token:, endpoint: Host.api_endpoint, retry_delay: 0.3, logger: Rails.logger)
      raise Trackers::Error.new("This GitLab connection holds no token", code: "not_authorized") if token.blank?

      @token = token
      @endpoint = endpoint.to_s.chomp("/")
      @retry_delay = retry_delay
      @logger = logger
    end

    def get(path, params = {}) = request(:get, path, params: params)
    def post(path, body = {}) = request(:post, path, body: body)
    def put(path, body = {}) = request(:put, path, body: body)
    def delete(path) = request(:delete, path)

    # Every item of a list endpoint, up to `limit`, following GitLab's page headers.
    def paginate(path, params = {}, limit: 1000)
      items = []
      page = 1
      MAX_PAGES.times do
        batch, headers = request(:get, path, params: params.merge(per_page: 100, page: page), with_headers: true)
        items.concat(Array(batch))
        page = headers["x-next-page"].to_s
        break if page.blank? || items.size >= limit
      end
      items.first(limit)
    end

    # One Trackers::UploadFile as multipart `file` (the uploads API).
    def upload(path, file)
      parts = [ [ "file", file.io, { filename: file.filename, content_type: file.content_type.presence || "application/octet-stream" } ] ]
      files.send_request(:post, "#{@endpoint}#{path}", headers: auth.merge("Accept" => "application/json"), parts: parts).json
    end

    def download(path, io:, max_bytes:)
      files.download("#{@endpoint}#{path}", io: io, max_bytes: max_bytes, headers: auth)
    end

    private

    def request(method, path, params: {}, body: nil, with_headers: false, attempt: 0)
      response = connection.run_request(method, path_for(path), body && body.to_json, headers(body)) do |req|
        req.params.update(params.compact.transform_keys(&:to_s)) if params.present?
      end
      log(method, path, response)
      if response.success?
        parsed = response.body.present? ? JSON.parse(response.body) : {}
        return with_headers ? [ parsed, response.headers ] : parsed
      end

      if method == :get && (response.status >= 500 || response.status == 429) && attempt < MAX_RETRIES
        sleep(@retry_delay * (2**attempt))
        return request(method, path, params: params, body: body, with_headers: with_headers, attempt: attempt + 1)
      end
      raise error_for(method, response)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise Trackers::Error::OutcomeUnknown, "GitLab did not answer (#{e.class})" unless method == :get

      raise Trackers::Error.new("GitLab did not answer (#{e.class})", code: "timeout")
    rescue JSON::ParserError
      raise Trackers::Error.new("GitLab answered with something other than JSON — check GITLAB_ENDPOINT", code: "provider_error")
    end

    def error_for(method, response)
      message = provider_message(response)
      case response.status
      when 401 then Trackers::Error.new("GitLab rejected this connection's token", code: "not_authorized")
      when 403 then Trackers::Error.new(message || "GitLab does not let this connection do that", code: "permission_denied")
      when 404 then Trackers::Error.new(message || "GitLab has no such resource, or this connection cannot see it", code: "not_found")
      when 409 then Trackers::Error::Conflict.new(message || "GitLab refused a conflicting change")
      when 429 then Trackers::Error.new("GitLab is rate limiting this connection", code: "rate_limited",
                                                                                  details: { retry_after: response.headers["retry-after"] })
      when 400..499 then Trackers::Error.new(message || "GitLab refused the request (#{response.status})", code: "validation_failed")
      else
        return Trackers::Error::OutcomeUnknown.new("GitLab failed (#{response.status}) on a write") unless method == :get

        Trackers::Error.new("GitLab failed (#{response.status})", code: "provider_error")
      end
    end

    # GitLab's errors: { message: "…" | { field: [..] } } or { error: "…" }.
    def provider_message(response)
      body = JSON.parse(response.body.to_s)
      return unless body.is_a?(Hash)

      raw = body["message"] || body["error_description"] || body["error"]
      text = raw.is_a?(Hash) ? raw.map { |field, errors| "#{field} #{Array(errors).join(', ')}" }.join("; ") : Array(raw).join("; ")
      text.presence&.truncate(300)
    rescue JSON::ParserError
      nil
    end

    def path_for(path) = "#{URI.parse(@endpoint).path}#{path}"

    def headers(body)
      base = auth.merge("Accept" => "application/json")
      base["Content-Type"] = "application/json" if body
      base
    end

    def auth = { "Authorization" => "Bearer #{@token}" }

    def connection
      @connection ||= Faraday.new(url: @endpoint.sub(%r{(https?://[^/]+).*}, '\1')) do |f|
        f.options.open_timeout = AppConfig.open_timeout
        f.options.timeout = AppConfig.read_timeout
        # No redirect middleware: a followed redirect would resend the token.
        f.adapter Faraday.default_adapter
      end
    end

    def files
      host = URI.parse(@endpoint).host
      @files ||= Trackers::FileTransfer.new(name: "GitLab", hosts: [ host ], open_timeout: AppConfig.open_timeout,
                                            trusted_hosts: [ host ], logger: @logger)
    end

    # The path only: query strings carry search text.
    def log(method, path, response)
      @logger.info("[Gitlab::Rest] #{method.to_s.upcase} #{path.split('?').first} status=#{response.status}")
    end
  end
end
