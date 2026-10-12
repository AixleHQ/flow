# frozen_string_literal: true

module AixleInsights
  # Thin client for the Aixle Insights OTLP/JSON logs collector. Deployment-level
  # config (collector origin, timeouts) comes from Settings.aixle_insights.*; the
  # ingest token is a PER-CALL argument — it is the company's Insights-org token
  # (an Integration row, Task 1b), and one client call serves one company.
  #
  # The collector answers `200 {"partialSuccess":{}}` on accept. It returns 200
  # even for an invalid token, so a 200 is "accepted for ingestion", NOT proof
  # the token was valid or that attribution will succeed — that is resolved
  # asynchronously inside Insights. Non-2xx is a delivery failure the caller
  # (the exporter's ledger, Task 6) replays.
  class Client
    class Error < StandardError; end

    PATH = "/v1/logs"

    class << self
      # POST an OTLP/JSON logs payload (built by OtlpLogsBuilder, Task 4) with
      # the given company token. Returns the parsed response body on a 2xx.
      # Raises Client::Error on a non-2xx or an unparseable body, with the
      # status logged — the exporter turns that into a `failed!` ledger row.
      def post_logs(payload:, token:)
        resp = connection.post(PATH) do |req|
          req.headers["Authorization"] = "Bearer #{token}"
          req.headers["Content-Type"] = "application/json"
          req.body = payload.to_json
        end

        unless resp.success?
          Rails.logger.warn("[AixleInsights::Client] collector returned #{resp.status}: #{resp.body.to_s.truncate(500)}")
          raise Error, "insights_collector_#{resp.status}"
        end

        parse(resp)
      end

      private

      def connection
        Faraday.new(url: base_url) do |f|
          f.request :retry, max: 2, interval: 0.2
          f.options.open_timeout = Settings.aixle_insights.open_timeout
          f.options.timeout = Settings.aixle_insights.read_timeout
          f.adapter Faraday.default_adapter
        end
      end

      def base_url
        url = Settings.aixle_insights.base_url
        raise Error, "insights_base_url_missing" if url.blank?

        url
      end

      # The collector's accept body is `{"partialSuccess":{}}`; an empty body is
      # also a valid 2xx. Return a hash either way; never fail a delivered batch
      # on a body quirk.
      def parse(resp)
        body = resp.body.to_s
        return {} if body.blank?

        JSON.parse(body)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
