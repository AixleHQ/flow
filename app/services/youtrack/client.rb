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

    def assert_selected_project!(issue)
      actual = issue.to_h.dig("project", "id").to_s
      raise Error, "YouTrack issue is outside the connected project" unless actual == @integration.youtrack_project_id
      issue
    end

    private

    def request(method, path, params: {}, body: nil)
      url = "#{@base_url}#{path}"
      uri = URI.parse(url)
      uri.query = URI.encode_www_form(params.compact) if params.present?
      errors = UrlSafetyValidator.errors_for(uri.to_s, require_https: true)
      raise Error, "Unsafe YouTrack URL: #{errors.first}" if errors.any?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 15
      request = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["Accept"] = "application/json"
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end
      response = http.request(request)
      raise Error, "YouTrack redirects are not allowed" if response.is_a?(Net::HTTPRedirection)
      raise AuthenticationError, "YouTrack authentication or permission denied" if [401, 403].include?(response.code.to_i)
      raise NotFoundError, "YouTrack resource not found" if response.code.to_i == 404
      raise Error, "YouTrack request failed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
      raise Error, "YouTrack response is too large" if response.body.to_s.bytesize > MAX_BYTES
      response.body.blank? ? {} : JSON.parse(response.body)
    rescue JSON::ParserError, URI::InvalidURIError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise Error, "YouTrack request failed: #{e.class.name.demodulize}"
    end

    def escape(value) = CGI.escapeURIComponent(value.to_s)
    def default_issue_fields = "id,idReadable,summary,description,project(id,name,shortName),customFields(id,name,value(id,name,login))"
  end
end
