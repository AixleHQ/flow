# frozen_string_literal: true

require "stringio"
require "zlib"

module Antigravity
  # Antigravity::Api — thin HTTP API layer for Google's Antigravity model
  # catalogue endpoint.
  #
  # Mirrors Codex::Api's separation of concerns: this layer owns the
  # transport — host, path, request/response shape, gzip decoding, JSON
  # parsing — while `Agents::AntigravityCliAdapter` keeps the domain logic of
  # which models to expose to the picker and when to fall back to the static
  # catalogue.
  class Api
    class ApiError < StandardError; end

    MODELS_URL = "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
    CONSUMER_PROJECT = "aicode-consumers"

    class << self
      # The raw `fetchAvailableModels` response body.
      #
      # @param access_token [String]
      # @return [Hash]
      # @raise [ApiError] on any transport, status, or parse failure
      def models(access_token:)
        uri = URI(MODELS_URL)
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["Content-Type"] = "application/json"
        request["Accept-Encoding"] = "gzip"
        request.body = { project: CONSUMER_PROJECT }.to_json

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
          http.request(request)
        end
        raise ApiError, "models failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        parse_json(response)
      rescue ApiError
        raise
      rescue StandardError => e
        raise ApiError, "models failed: #{e.message}"
      end

      private

      def parse_json(response)
        JSON.parse(response_body(response))
      rescue JSON::ParserError => e
        raise ApiError, "models failed: invalid JSON response (#{e.message})"
      end

      def response_body(response)
        return response.body unless response["Content-Encoding"].to_s.downcase.include?("gzip")

        Zlib::GzipReader.new(StringIO.new(response.body)).read
      end
    end
  end
end
