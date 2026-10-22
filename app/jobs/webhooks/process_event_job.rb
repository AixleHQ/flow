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
        received.update!(status: "skipped", raw_payload: scrubbed_payload(endpoint, received.raw_payload))
        return
      end

      source = "#{endpoint.provider}:#{endpoint.slug}"
      dedup_key = "#{endpoint.provider}:#{received.idempotency_key}"
      if Chat.provider(endpoint.provider)
        # A chat workspace serves every company that connected it.
        Chat::WorkspaceRouter.call(endpoint: endpoint, normalized: normalized, source: source, dedup_key: dedup_key)
      else
        TriggerEngine.publish(event_type: normalized[:event_type], source: source, subject: normalized[:subject],
                              data: normalized[:data], project: endpoint.project, company: endpoint.company,
                              dedup_key: dedup_key)
      end

      received.update!(status: "processed", raw_payload: scrubbed_payload(endpoint, received.raw_payload))
    end

    private

    # A delivery keeps no file link once handled; the event keeps its own
    # until it has been dispatched (TriggerEngine.dispatch_pending).
    def scrubbed_payload(endpoint, payload)
      provider = Chat.provider(endpoint.provider)
      provider ? provider.scrub_payload(payload) : payload
    end

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
