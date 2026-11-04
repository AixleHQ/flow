# frozen_string_literal: true

module Analytics
  # The PostHog capture API, for the events the server sends. The only place
  # that knows PostHog's wire format; everything else goes through Analytics.
  class Client
    class Error < StandardError; end

    def configured? = Settings.posthog.api_key.present?

    # `events` are hashes with event, distinct_id, properties, timestamp, uuid.
    # The uuid lets PostHog drop a batch that a retried job sends twice.
    def capture_batch(events)
      response = connection.post("batch/") do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = { api_key: Settings.posthog.api_key, batch: events }.to_json
      end
      raise Error, "PostHog answered #{response.status}" unless response.success?

      true
    rescue Faraday::Error => e
      raise Error, e.message
    end

    private

    def connection
      Faraday.new(url: "#{Settings.posthog.host.to_s.chomp('/')}/") do |f|
        f.options.open_timeout = 3
        f.options.timeout = 5
        f.adapter Faraday.default_adapter
      end
    end
  end
end
