# frozen_string_literal: true

module Webhooks
  # Async second half of inbound webhook handling: take a stored ReceivedWebhook,
  # normalize the provider payload into a CloudEvents-style TriggerEvent, and
  # publish it so the TriggerEngine matches it against TriggerBinding rules.
  class ProcessEventJob < ApplicationJob
    queue_as :default

    def perform(received_webhook_id)
      received = ReceivedWebhook.find_by(id: received_webhook_id)
      return if received.nil? || received.status == "processed"

      endpoint = received.webhook_endpoint
      normalized = normalize(endpoint, received.raw_payload)

      if normalized.nil?
        received.update!(status: "skipped")
        return
      end

      TriggerEngine.publish(
        event_type: normalized[:event_type],
        source: "#{endpoint.provider}:#{endpoint.slug}",
        subject: normalized[:subject],
        data: normalized[:data],
        project: endpoint.project,
        dedup_key: "#{endpoint.provider}:#{received.idempotency_key}"
      )

      received.update!(status: "processed")
    end

    private

    # Provider-specific payload → normalized event. Returns nil to skip.
    def normalize(endpoint, payload)
      case endpoint.provider.to_s
      when "slack"   then normalize_slack(payload)
      else                normalize_generic(endpoint, payload)
      end
    end

    def normalize_slack(payload)
      event = payload["event"]
      return nil unless event.is_a?(Hash)

      kind = event["type"].to_s # "message", "app_mention", "reaction_added", ...
      return nil if kind.blank?
      return nil if event["bot_id"].present? # ignore the bot's own messages

      {
        event_type: "slack.message",
        subject: event["channel"],
        data: {
          "slack_event_type" => kind,
          "channel" => event["channel"],
          "user" => event["user"],
          "text" => event["text"],
          "team" => payload["team_id"]
        }.compact
      }
    end

    def normalize_generic(endpoint, payload)
      {
        event_type: endpoint.config["event_type"].presence || "webhook.received",
        subject: nil,
        data: payload.is_a?(Hash) ? payload : { "body" => payload }
      }
    end
  end
end
