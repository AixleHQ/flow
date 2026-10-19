# frozen_string_literal: true

require "net/http"

module Trackers
  # Bytes to and from a tracker: the one place the rules of
  # docs/design/tracker-attachments.md §9.1 live.
  #
  # - A request goes only to a host on `hosts`, through SafeHttp, so a URL read
  #   out of an issue cannot reach anything private.
  # - A redirect is followed only on a download, only to `redirect_hosts`, and
  #   without the caller's headers: Jira's and GitHub's signed media hosts take
  #   no credential, and forwarding one would hand it to another host.
  # - A body is streamed into the caller's IO and refused past `max_bytes`.
  #
  # Errors come back as Trackers::Error. A write that left and was never
  # answered is OutcomeUnknown, as in the providers' own clients.
  class FileTransfer
    MAX_REDIRECTS = 3
    MAX_RESPONSE_BYTES = 4.megabytes
    REDIRECTS = [ 301, 302, 303, 307, 308 ].freeze

    Response = Data.define(:status, :headers, :body) do
      def json
        body.blank? ? {} : JSON.parse(body)
      rescue JSON::ParserError
        raise Error.new("The tracker answered with something other than JSON", code: "provider_error")
      end
    end

    # `hosts` and `redirect_hosts` hold host names, or regexps a whole host name must match.
    def initialize(name:, hosts:, redirect_hosts: [], open_timeout: 10, read_timeout: 120, trusted_hosts: [],
                   logger: Rails.logger)
      @name = name
      @hosts = Array(hosts)
      @redirect_hosts = Array(redirect_hosts)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @trusted_hosts = trusted_hosts
      @logger = logger
    end

    # Streams `url` into `io`. `reauthorize`, when given, is called once after a
    # 401 and returns fresh headers. Returns { content_type:, size: }.
    def download(url, io:, max_bytes:, headers: {}, reauthorize: nil)
      uri = permitted!(url, @hosts)
      MAX_REDIRECTS.succ.times do
        io.rewind
        io.truncate(0) if io.respond_to?(:truncate)
        response, size = stream(uri, headers, io, max_bytes)
        status = response.code.to_i
        if REDIRECTS.include?(status)
          uri = permitted!(URI.join(uri.to_s, response["location"].to_s).to_s, @redirect_hosts)
          headers = {}
          next
        end
        if status == 401 && reauthorize
          headers = reauthorize.call
          reauthorize = nil
          next
        end
        raise error_for(:get, status, nil) unless status.between?(200, 299)

        io.rewind
        return { content_type: response["content-type"].to_s.split(";").first.presence, size: size }
      end
      raise Error.new("#{@name} redirected the download too many times", code: "provider_error")
    end

    # A request with a body: `parts` for multipart/form-data
    # ([[field, io, { filename:, content_type: }]]), or `body` (an IO) sent as
    # `content_type`. Redirects are not followed. Returns a Response.
    def send_request(method, url, headers: {}, parts: nil, body: nil, content_type: nil, size: nil,
                     reauthorize: nil)
      uri = permitted!(url, @hosts)
      2.times do
        response, text = perform(build(method, uri, headers, parts, body, content_type, size))
        status = response.code.to_i
        return Response.new(status: status, headers: response.to_hash, body: text) if status.between?(200, 299)

        if status == 401 && reauthorize
          headers = reauthorize.call
          reauthorize = nil
          [ body, *Array(parts).map { |part| part[1] } ].compact.each(&:rewind)
          next
        end
        raise error_for(method, status, text)
      end
    end

    private

    def permitted!(url, hosts)
      uri = URI.parse(url.to_s)
      raise Error.new("#{@name} files are fetched over https only", code: "validation_failed") unless uri.scheme == "https"

      host = uri.host.to_s.downcase
      allowed = hosts.any? { |h| h.is_a?(Regexp) ? h.match?(host) : h.to_s.casecmp?(host) }
      raise Error.new("#{@name} pointed at a host Aixle does not fetch files from: #{host}", code: "not_found") unless allowed

      uri
    rescue URI::InvalidURIError
      raise Error.new("#{@name} gave a file address that is not a URL", code: "provider_error")
    end

    def stream(uri, headers, io, max_bytes)
      size = 0
      response = connection(uri).start do |http|
        http.request(get(uri, headers)) do |incoming|
          next unless incoming.code.to_i.between?(200, 299)

          incoming.read_body do |chunk|
            size += chunk.bytesize
            if size > max_bytes
              raise Error.new("The file is larger than #{max_bytes / 1.megabyte} MB", code: "too_large",
                                                                                      details: { max_bytes: max_bytes })
            end
            io.write(chunk)
          end
        end
      end
      log(:get, uri, response)
      [ response, size ]
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
           EOFError, OpenSSL::SSL::SSLError => e
      raise Error.new("#{@name} did not answer (#{e.class.name.demodulize})", code: "timeout")
    rescue SafeHttp::UnsafeUrl => e
      raise Error.new("#{@name} file address #{e.message}", code: "validation_failed")
    end

    def perform(request)
      uri = request.uri
      text = +""
      response = connection(uri).start do |http|
        http.request(request) do |incoming|
          incoming.read_body do |chunk|
            text << chunk
            raise Error.new("#{@name}'s answer is too large", code: "provider_error") if text.bytesize > MAX_RESPONSE_BYTES
          end
        end
      end
      log(request.method, uri, response)
      [ response, text ]
    rescue Net::OpenTimeout, SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      raise Error.new("#{@name} could not be reached (#{e.class.name.demodulize})", code: "timeout")
    rescue Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNRESET, Errno::EPIPE, EOFError, OpenSSL::SSL::SSLError => e
      raise Error::OutcomeUnknown, "#{@name} did not answer (#{e.class.name.demodulize})"
    rescue SafeHttp::UnsafeUrl => e
      raise Error.new("#{@name} upload address #{e.message}", code: "validation_failed")
    end

    def connection(uri)
      http = SafeHttp.http_for(uri, open_timeout: @open_timeout, read_timeout: @read_timeout, trusted_hosts: @trusted_hosts)
      http.write_timeout = @read_timeout
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http
    end

    def get(uri, headers)
      request = Net::HTTP::Get.new(uri)
      headers.each { |key, value| request[key] = value }
      request
    end

    def build(method, uri, headers, parts, body, content_type, size)
      klass = { post: Net::HTTP::Post, put: Net::HTTP::Put }.fetch(method)
      request = klass.new(uri)
      headers.each { |key, value| request[key] = value }
      if parts
        request.set_form(parts, "multipart/form-data")
      elsif body
        request.body_stream = body
        request["Content-Type"] = content_type if content_type
        request["Content-Length"] = size.to_s
      end
      request
    end

    def error_for(method, status, text)
      message = text.to_s.truncate(300) if text.present? && !text.lstrip.start_with?("<")
      case status
      when 401 then Error.new("#{@name} rejected this connection's credential", code: "not_authorized")
      when 403 then Error.new("#{@name} does not let this connection touch that file", code: "permission_denied")
      when 404 then Error.new("#{@name} has no such file, or this connection cannot see it", code: "not_found")
      when 409 then Error::Conflict.new("#{@name} refused a conflicting change")
      when 413 then Error.new("#{@name} refused the file as too large", code: "too_large")
      when 429 then Error.new("#{@name} is rate limiting this connection", code: "rate_limited")
      when 400..499
        Error.new("#{@name} refused the file (#{status})#{": #{message}" if message}", code: "validation_failed")
      else
        return Error::OutcomeUnknown.new("#{@name} failed (#{status}) on an upload") unless method == :get

        Error.new("#{@name} failed (#{status})", code: "provider_error")
      end
    end

    # Never the query string: signed URLs carry their credential there.
    def log(method, uri, response)
      @logger.info("[Trackers::FileTransfer] #{@name} #{method.to_s.upcase} #{uri.host}#{uri.path} status=#{response.code}")
    end
  end
end
