# frozen_string_literal: true

require "net/http"
require "timeout"

module Engram
  class Client
    class Unavailable < StandardError; end

    def self.build
      new
    end

    def self.configured?
      Settings.engram.url.present?
    end

    def initialize(url: Settings.engram.url, max_response_bytes: 1.megabyte, token: Settings.engram.http_token)
      @origin = URI.parse(url.to_s)
      unless %w[http https].include?(@origin.scheme) && @origin.host.present? && @origin.userinfo.nil? &&
          [ "", "/" ].include?(@origin.path) && @origin.query.nil? && @origin.fragment.nil?
        raise Unavailable, "Project memory is unavailable"
      end
      @max_response_bytes = max_response_bytes
      @token = token
    rescue URI::InvalidURIError
      raise Unavailable, "Project memory is unavailable", cause: nil
    end

    def search(project:, query:, limit:)
      rows = request(Net::HTTP::Get, "/search", params: { q: query, project: project, scope: "project", limit: limit })
      raise Unavailable, "Project memory is unavailable" unless rows.is_a?(Array)

      rows.map do |row|
        unless row.is_a?(Hash) && row["id"].is_a?(Integer) && row["id"].positive? &&
            %w[title content project].all? { |field| row[field].is_a?(String) }
          raise Unavailable, "Project memory is unavailable"
        end
        row.slice("id", "title", "content", "project")
      end
    end

    def save(project:, title:, content:, topic_key:)
      session = request(Net::HTTP::Post, "/sessions", body: {
        id: "flow-#{SecureRandom.uuid}", project: project, ownership_mode: "project_owned", isolated: true
      })
      unless session.is_a?(Hash) && session["id"].is_a?(String) && session["id"].present?
        raise Unavailable, "Project memory is unavailable"
      end

      result = request(Net::HTTP::Post, "/observations", body: {
        session_id: session["id"], project: project, title: title, content: content,
        topic_key: topic_key, type: "summary", scope: "project", capture_prompt: false
      })
      unless result.is_a?(Hash) && result["id"].is_a?(Integer) && result["id"].positive?
        raise Unavailable, "Project memory is unavailable"
      end

      result["id"]
    end

    def delete(id:, project:)
      raise Unavailable, "Project memory is unavailable" unless id.to_s.match?(/\A[1-9]\d*\z/)

      request(Net::HTTP::Delete, "/observations/#{id}", params: { hard: true, expected_project: project }, missing_ok: true)
      true
    end

    private

    def request(method, path, params: nil, body: nil, missing_ok: false)
      uri = @origin.dup
      uri.path = path
      uri.query = URI.encode_www_form(params) if params
      message = method.new(uri)
      message["Accept"] = "application/json"
      message["Authorization"] = "Bearer #{@token}" if @token.present?
      if body
        message["Content-Type"] = "application/json"
        message.body = JSON.generate(body)
      end
      bytes = +""
      http = Net::HTTP.new(uri.host, uri.port, nil)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 2
      http.read_timeout = 3
      http.write_timeout = 3
      http.max_retries = 0
      Timeout.timeout(3, Unavailable) do
        http.start do |connection|
          connection.request(message) do |response|
            return {} if missing_ok && response.is_a?(Net::HTTPNotFound)

            raise Unavailable, "Project memory is unavailable" unless response.is_a?(Net::HTTPSuccess)

            response.read_body do |chunk|
              raise Unavailable, "Project memory is unavailable" if bytes.bytesize + chunk.bytesize > @max_response_bytes

              bytes << chunk
            end
          end
        end
      end
      JSON.parse(bytes)
    rescue StandardError
      raise Unavailable, "Project memory is unavailable", cause: nil
    end
  end
end
