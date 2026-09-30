# frozen_string_literal: true

module Youtrack
  class Client
    Error = Class.new(StandardError)
    AuthenticationError = Class.new(Error)
    NotFoundError = Class.new(Error)
    MAX_BYTES = 512.kilobytes

    def initialize(integration)
      @integration = integration
      @base_url = integration.youtrack_base_url.to_s.chomp("/")
      @token = integration.youtrack_token.to_s
    end

    def get(path, params = {}) = request(:get, path, params: params)
    def post(path, body = {}) = request(:post, path, body: body)

    def checked_issue(id, fields: default_issue_fields)
      issue = get("/api/issues/#{escape(id)}", fields: fields)
      assert_selected_project!(issue)
      issue
    end

    def me = get("/api/users/me", fields: "id,login,name")
    def project(id) = get("/api/admin/projects/#{escape(id)}", fields: "id,name,shortName")

    def assert_selected_project!(issue)
      actual = issue.to_h.dig("project", "id").to_s
      raise Error, "YouTrack issue is outside the connected project" unless actual == @integration.youtrack_project_id
      issue
    end

    private

    def request(method, path, params: {}, body: nil)
      if @integration.id && !Integration.active.exists?(id: @integration.id)
        raise Error, "YouTrack is not connected for this project"
      end
      url = "#{@base_url}#{path}"
      uri = URI.parse(url)
      uri.query = URI.encode_www_form(params.compact) if params.present?
      errors = UrlSafetyValidator.errors_for(uri.to_s, require_https: true)
      raise Error, "Unsafe YouTrack URL: #{errors.first}" if errors.any?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 15
      # Pin the address checked by UrlSafetyValidator. A second DNS lookup at
      # connect time could otherwise send the bearer token to an internal host.
      unless UrlSafetyValidator.ip_or_nil(uri.host)
        addresses = UrlSafetyValidator.resolved_addresses(uri.host)
        trusted = UrlSafetyValidator.trusted_host?(uri.host)
        ip = addresses.find { |address| trusted || !UrlSafetyValidator.blocked_ip?(address) }
        raise Error, "YouTrack host could not be resolved safely" unless ip
        http.ipaddr = ip.to_s
      end
      request = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["Accept"] = "application/json"
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end
      body_text = +""
      response = http.request(request) do |incoming|
        incoming.read_body do |chunk|
          body_text << chunk
          raise Error, "YouTrack response is too large" if body_text.bytesize > MAX_BYTES
        end
      end
      raise Error, "YouTrack redirects are not allowed" if response.is_a?(Net::HTTPRedirection)
      raise AuthenticationError, "YouTrack authentication or permission denied" if [ 401, 403 ].include?(response.code.to_i)
      raise NotFoundError, "YouTrack resource not found" if response.code.to_i == 404
      raise Error, "YouTrack request failed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
      body_text.blank? ? {} : JSON.parse(body_text)
    rescue JSON::ParserError, URI::InvalidURIError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise Error, "YouTrack request failed: #{e.class.name.demodulize}"
    end

    def escape(value) = CGI.escapeURIComponent(value.to_s)
    def default_issue_fields = "id,idReadable,summary,description,project(id,name,shortName),customFields(id,name,value(id,name,login))"
  end
end
