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

      # Chat endpoints are company-scoped (one workspace or tenant serves every
      # project of the company) → company-wide fan-out. Other endpoints stay
      # project-scoped.
      TriggerEngine.publish(
        event_type: normalized[:event_type],
        source: "#{endpoint.provider}:#{endpoint.slug}",
        subject: normalized[:subject],
        data: normalized[:data],
        project: endpoint.project,
        company: endpoint.company,
        dedup_key: "#{endpoint.provider}:#{received.idempotency_key}"
      )

      received.update!(status: "processed")
    end

    private

    # Provider-specific payload → normalized event. Returns nil to skip.
    def normalize(endpoint, payload)
      case endpoint.provider.to_s
      when "slack"   then Chat::SlackProvider.normalize(endpoint, payload)
      when "teams"   then Chat::TeamsProvider.normalize(endpoint, payload)
      else                normalize_generic(endpoint, payload)
      end
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
