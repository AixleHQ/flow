# frozen_string_literal: true

module Webhooks
  # A run started through the generic gateway: the body the sender posted is
  # the run's input, so the run carries it for every step's agent.
  module TriggerSupport
    PAYLOAD_PATH = "#{Asset::CONTAINER_DIR}/webhook-payload.json".freeze

    module_function

    # A chat provider turns its deliveries into its own message shape; every
    # other endpoint's event data is the request body (Webhooks::ProcessEventJob).
    def event?(event)
      provider = event&.source.to_s.split(":", 2).first
      WebhookEndpoint.provider.values.include?(provider) && Chat.provider(provider).nil?
    end

    def run_context(event)
      return {} unless event?(event)

      { "webhook" => { "payload" => event.data.to_h } }
    end

    def payload(workflow_run)
      workflow_run&.shared_context.to_h.dig("webhook", "payload")
    end
  end
end
