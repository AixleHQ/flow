# frozen_string_literal: true

require "net/http"
require "zlib"

module Insights
  # The partner API of Aixle Insights (docs/design/insights-otlp-relay.md §3–§5 and the
  # interface contract agreed with Insights). The deployment credential is sent only to
  # redeem a pairing code; everything else carries the connection's own secret.
  #
  # The URL is the operator's (Settings.insights.url), never a user's, so this does not
  # go through SafeHttp — and a self-hosted Insights may well sit on a private address.
  class Client
    TIMEOUT = 10
    BASE_PATH = "/partner/v1"

    class Error < StandardError
      attr_reader :status, :code, :retry_after

      def initialize(message, status: nil, code: nil, retry_after: nil)
        super(message)
        @status = status
        @code = code
        @retry_after = retry_after
      end

      def unauthorized? = status == 401
    end

    # The answer to one export request: status, the OTLP partial-success count, and the
    # Retry-After of a 429 or 503.
    ExportResult = Struct.new(:status, :rejected, :message, :retry_after, keyword_init: true) do
      def accepted? = status.to_i.between?(200, 299) && rejected.to_i.zero?
      def partially_rejected? = status.to_i.between?(200, 299) && rejected.to_i.positive?
    end

    def self.build = new(url: Settings.insights.url)

    def initialize(url:)
      @base = URI.parse(url.to_s.chomp("/"))
    end

    # Redeems an owner's one-time code for a connection and its secret.
    def claim(code:, company_id:, company_name:, deployment_id:, deployment_secret:)
      request = Net::HTTP::Post.new(path("/connections/claim"))
      request.basic_auth(deployment_id, deployment_secret)
      json!(request, { code: code.to_s.delete("-").strip, company: { id: company_id, name: company_name } })
      body = perform!(request)
      { connection_id: body.fetch("connection_id"), secret: body.fetch("secret"),
        organization_id: body.dig("organization", "id"), organization_name: body.dig("organization", "name") }
    end

    def projects(secret)
      perform!(authorized(Net::HTTP::Get.new(path("/connection/projects")), secret)).fetch("projects", [])
    end

    # A new secret; the one it was called with keeps working for an hour on Insights' side.
    def rotate(secret)
      perform!(authorized(Net::HTTP::Post.new(path("/connection/rotate")), secret)).fetch("secret")
    end

    # A 401 means the secret no longer works — revoked by the owner, or by an earlier
    # disconnect whose answer was lost — which is the outcome asked for.
    def disconnect(secret)
      perform!(authorized(Net::HTTP::Delete.new(path("/connection")), secret))
      true
    rescue Error => e
      raise unless e.unauthorized?

      true
    end

    REJECTED = { "logs" => "rejectedLogRecords", "metrics" => "rejectedDataPoints", "traces" => "rejectedSpans" }.freeze

    # One OTLP/HTTP JSON export request of the signal — the agents' own records, enriched
    # by Flow — gzipped.
    def export(secret, signal, payload)
      request = authorized(Net::HTTP::Post.new(path("/otlp/v1/#{signal}")), secret)
      request["Content-Type"] = "application/json"
      request["Content-Encoding"] = "gzip"
      request.body = Zlib.gzip(payload.to_json)
      response = send_request(request)
      body = parse(response.body)
      partial = body["partialSuccess"].is_a?(Hash) ? body["partialSuccess"] : {}
      ExportResult.new(status: response.code.to_i, rejected: partial[REJECTED.fetch(signal)].to_i,
                       message: partial["errorMessage"].presence || body["error"],
                       retry_after: retry_after(response))
    end

    private

    def path(suffix) = "#{@base.path}#{BASE_PATH}#{suffix}"

    def authorized(request, secret)
      request["Authorization"] = "Bearer #{secret}"
      request
    end

    def json!(request, body)
      request["Content-Type"] = "application/json"
      request.body = body.to_json
    end

    def perform!(request)
      response = send_request(request)
      body = parse(response.body)
      return body if response.is_a?(Net::HTTPSuccess)

      raise Error.new(body["error"].presence || "Insights answered #{response.code}",
                      status: response.code.to_i, code: body["error"], retry_after: retry_after(response))
    end

    def send_request(request)
      request["Accept"] = "application/json"
      Net::HTTP.start(@base.host, @base.port, use_ssl: @base.scheme == "https",
                                              open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(request)
      end
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
      raise Error.new("Insights is unreachable: #{e.class}")
    end

    def parse(body)
      return {} if body.blank?

      parsed = JSON.parse(body)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def retry_after(response)
      value = response["Retry-After"]
      value&.match?(/\A\d+\z/) ? value.to_i : nil
    end
  end
end
