# frozen_string_literal: true

require "net/http"

module Youtrack
  # REST client for one YouTrack instance, failing with Trackers::Error.
  #
  # The base URL is the customer's, possibly a self-hosted server, so every
  # request goes through SafeHttp: the host is resolved once, refused when it is
  # private, and dialed at the address that was checked. Only https; redirects
  # are not followed (one would resend the token); the body is bounded.
  #
  # Only a read is retried: a write that failed on the server may have landed.
  class Client
    MAX_BYTES = 4.megabytes
    MAX_RETRIES = 2
    RETRYABLE = [ 502, 503, 504 ].freeze

    def initialize(base_url:, token:, retry_delay: 0.3, logger: Rails.logger)
      @base_url = base_url.to_s.chomp("/")
      @token = token.to_s
      @retry_delay = retry_delay
      @logger = logger
    end

    def get(path, params = {}) = request(:get, path, params: params)
    def post(path, body, params = {}) = request(:post, path, params: params, body: body)
    def delete(path) = request(:delete, path)

    private

    def request(method, path, params: {}, body: nil, attempt: 0)
      uri = uri_for(path, params)
      response, text = perform(method, uri, body)
      log(method, uri, response)
      status = response.code.to_i
      return parse(text) if status.between?(200, 299)

      if method == :get && RETRYABLE.include?(status) && attempt < MAX_RETRIES
        sleep(@retry_delay * (2**attempt))
        return request(method, path, params: params, body: body, attempt: attempt + 1)
      end
      raise error_for(method, status, text)
    rescue Net::OpenTimeout, SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      raise Trackers::Error.new("YouTrack could not be reached (#{e.class.name.demodulize})", code: "timeout")
    rescue Net::ReadTimeout, Errno::ECONNRESET, EOFError, OpenSSL::SSL::SSLError => e
      raise Trackers::Error::OutcomeUnknown, "YouTrack did not answer (#{e.class.name.demodulize})" unless method == :get

      raise Trackers::Error.new("YouTrack did not answer (#{e.class.name.demodulize})", code: "timeout")
    rescue SafeHttp::UnsafeUrl => e
      raise Trackers::Error.new("The YouTrack URL #{e.message}", code: "validation_failed")
    end

    def uri_for(path, params)
      uri = URI.parse("#{@base_url}#{path}")
      raise Trackers::Error.new("The YouTrack URL must use https", code: "validation_failed") unless uri.scheme == "https"

      query = params.compact.map { |key, value| [ key.to_s, value.to_s ] }
      uri.query = URI.encode_www_form(query) if query.any?
      uri
    rescue URI::InvalidURIError
      raise Trackers::Error.new("The YouTrack URL is not a URL", code: "validation_failed")
    end

    def perform(method, uri, body)
      http = SafeHttp.http_for(uri, open_timeout: Config.open_timeout, read_timeout: Config.read_timeout,
                                    trusted_hosts: Config.trusted_hosts)
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      text = +""
      response = http.start do |connection|
        connection.request(build(method, uri, body)) do |incoming|
          incoming.read_body do |chunk|
            text << chunk
            raise Trackers::Error.new("YouTrack's answer is too large", code: "provider_error") if text.bytesize > MAX_BYTES
          end
        end
      end
      [ response, text ]
    end

    def build(method, uri, body)
      request = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(method).new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["Accept"] = "application/json"
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end
      request
    end

    def parse(text)
      text.blank? ? {} : JSON.parse(text)
    rescue JSON::ParserError
      raise Trackers::Error.new("YouTrack answered with something other than JSON — is this the instance's URL?",
                                code: "provider_error")
    end

    def error_for(method, status, text)
      message = provider_message(text)
      case status
      when 300..399
        Trackers::Error.new("YouTrack redirected the request; enter the instance's final URL", code: "validation_failed")
      when 401 then Trackers::Error.new("YouTrack rejected the permanent token", code: "not_authorized")
      when 403 then Trackers::Error.new(message || "The token's account may not do this in YouTrack", code: "permission_denied")
      when 404 then Trackers::Error.new(message || "YouTrack has no such entity, or the token cannot see it", code: "not_found")
      when 409 then Trackers::Error::Conflict.new(message || "YouTrack refused a conflicting change")
      when 429 then Trackers::Error.new("YouTrack is rate limiting this connection", code: "rate_limited")
      when 400..499 then Trackers::Error.new(message || "YouTrack refused the request (#{status})", code: "validation_failed")
      else
        return Trackers::Error::OutcomeUnknown.new("YouTrack failed (#{status}) on a write") unless method == :get

        Trackers::Error.new("YouTrack failed (#{status})", code: "provider_error")
      end
    end

    def provider_message(text)
      body = JSON.parse(text.to_s)
      message = body["error_description"].presence || body["error"].presence if body.is_a?(Hash)
      message&.to_s&.truncate(300)
    rescue JSON::ParserError
      nil
    end

    # Ids and statuses only; a query string carries issue text and logins.
    def log(method, uri, response)
      @logger.info("[Youtrack::Client] #{method.upcase} #{uri.path} status=#{response.code}")
    end
  end
end
