# frozen_string_literal: true

module Trackers
  module Github
    # The tracker events of a GitHub App delivery, which Webhooks::GithubController
    # has authenticated with the App's webhook secret. One installation can back
    # a connection in several Aixle projects; each records the delivery against
    # its own subscription.
    #
    # GitHub sends every issue and comment of every repository the App can see,
    # so a delivery is recorded only for a connection a tracker trigger waits on.
    module Webhooks
      module_function

      def receive(event, payload, delivery_id:)
        installation_id = Integer(payload.dig("installation", "id"), exception: false)
        return unless installation_id && Notifications.tracked?(event, payload["action"])

        Integration.where(provider: "github", github_installation_id: installation_id).active.find_each do |integration|
          accept(integration, event, payload, delivery_id)
        end
      end

      def accept(integration, event, payload, delivery_id)
        return unless EventPipeline.awaited_by?(integration)

        provider = Provider.new(integration)
        notifications = provider.parse_event(event, payload)
        return if notifications.empty?

        subscription = provider.subscription
        subscription.update_columns(last_event_at: Time.current, status: "active", updated_at: Time.current)
        dedup_key = delivery_id.presence || Digest::SHA256.hexdigest(payload.to_json)
        delivery = TrackerDelivery.record(subscription: subscription, dedup_key: dedup_key, notifications: notifications)
        ProcessDeliveryJob.perform_later(delivery.id) if delivery
      end
    end
  end
end
