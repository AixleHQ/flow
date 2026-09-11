# frozen_string_literal: true

module AzureDevops
  # Creates, inspects and removes Azure DevOps Service Hook subscriptions for one
  # project connection.
  #
  # Automated setup needs organization-level permission the connection may not
  # have, so every failure here is reported rather than raised at the caller:
  # manual subscription setup is an acceptable first step, and a connection whose
  # subscriptions could not be created still works for everything on-demand.
  class SubscriptionService
    # Azure's own name for the consumer that POSTs JSON to a URL.
    CONSUMER = { consumerId: "webHooks", consumerActionId: "httpRequest", publisherId: "tfs" }.freeze

    def initialize(integration)
      @integration = integration
    end

    attr_reader :integration

    # Ensure a live subscription exists for each event type. Idempotent: an
    # existing live row is left alone rather than recreated, because recreating
    # one rotates its password and orphans the subscription Azure still holds.
    def ensure_all!(event_types: AzureDevopsSubscription::EVENT_TYPES, base_url: nil)
      event_types.filter_map do |event_type|
        # ANY existing row, not only a live one: the unique index is on
        # (integration, event_type), so a row left behind by an earlier failed
        # attempt must be reused rather than duplicated.
        existing = integration.azure_devops_subscriptions.find_by(event_type: event_type)
        next existing if existing&.azure_subscription_id.present? && existing.live?

        create!(event_type: event_type, base_url: base_url, subscription: existing)
      rescue Error => e
        Rails.logger.warn("[AzureDevops::SubscriptionService] #{event_type} failed for " \
                          "integration #{integration.id}: #{e.code}")
        nil
      end
    end

    def create!(event_type:, base_url: nil, subscription: nil)
      subscription ||= integration.azure_devops_subscriptions.find_or_initialize_by(event_type: event_type)
      subscription.save! if subscription.new_record?

      client, resolved = CredentialProvider.client_for(integration)
      payload = client.post(
        "_apis", "hooks", "subscriptions",
        body: CONSUMER.merge(
          eventType: event_type,
          publisherInputs: publisher_inputs(event_type, resolved),
          consumerInputs: {
            url: callback_url(subscription, base_url),
            # Azure's webhook consumer authenticates with HTTP basic auth and
            # sends no signature at all. These two are the entire credential.
            basicAuthUsername: "aixle",
            basicAuthPassword: subscription.password,
            # Without this Azure posts a "resourceContainers only" body; the
            # receiver re-reads authoritative state either way, but a detailed
            # payload is what lets it route without an extra call.
            resourceDetailsToSend: "all",
            messagesToSend: "none",
            detailedMessagesToSend: "none"
          }
        ),
        family: :default
      )

      subscription.update!(
        azure_subscription_id: payload["id"],
        status: :active,
        error_code: nil,
        last_checked_at: Time.current
      )
      subscription
    rescue Error => e
      subscription&.update(status: :error, error_code: e.code, last_checked_at: Time.current)
      raise e
    end

    # Ask Azure what state each subscription is actually in. A subscription on
    # probation is not delivering, and from this side that is indistinguishable
    # from "nothing has happened" — so it is read and recorded rather than
    # assumed healthy.
    def refresh_status!
      client, = CredentialProvider.client_for(integration)

      integration.azure_devops_subscriptions.find_each do |subscription|
        next if subscription.azure_subscription_id.blank?

        remote = client.get("_apis", "hooks", "subscriptions", subscription.azure_subscription_id, family: :default)
        subscription.update!(status: map_status(remote["status"]), last_checked_at: Time.current)
      rescue NotFound
        # Deleted in Azure's UI. Recorded as disabled rather than recreated
        # behind the operator's back.
        subscription.update!(status: :disabled, error_code: "deleted_upstream", last_checked_at: Time.current)
      rescue Error => e
        subscription.update!(error_code: e.code, last_checked_at: Time.current)
      end
    end

    # Best effort, and deliberately so: disconnect runs this while credentials
    # are still resolvable, but a failure must not block the disconnect. What is
    # left behind is a subscription posting to an endpoint that no longer
    # authenticates, which fails closed.
    def remove_all!
      client, = CredentialProvider.client_for(integration)

      integration.azure_devops_subscriptions.find_each do |subscription|
        if subscription.azure_subscription_id.present?
          begin
            client.request_delete("_apis", "hooks", "subscriptions", subscription.azure_subscription_id)
          rescue Error => e
            Rails.logger.warn("[AzureDevops::SubscriptionService] could not delete subscription " \
                              "#{subscription.azure_subscription_id}: #{e.code}")
          end
        end
        subscription.destroy
      end
    rescue Error => e
      Rails.logger.warn("[AzureDevops::SubscriptionService] cleanup skipped for integration " \
                        "#{integration.id}: #{e.code}")
      integration.azure_devops_subscriptions.update_all(status: "disabled", error_code: "cleanup_failed")
    end

    private

    # Scoped to the connection's own Azure project, so a subscription cannot
    # deliver events from elsewhere in the organization.
    def publisher_inputs(event_type, resolved)
      inputs = { projectId: resolved.project_id }
      inputs[:buildStatus] = "Completed" if event_type == "build.complete"
      inputs
    end

    # Same convention as Gitlab::RepositoryService's hook URL. Unlike the
    # on-demand half of this integration, Service Hooks are the one place that
    # needs a publicly reachable host: Azure posts INBOUND, so `localhost:4000`
    # produces a subscription Azure can create and never deliver to.
    def callback_url(subscription, base_url)
      root = base_url.presence || AppConfig.webhook_base_url
      raise CredentialActionRequired, "AZURE_DEVOPS_WEBHOOK_BASE_URL is not set" if root.blank?

      "#{root.to_s.chomp('/')}/webhooks/azure_devops/#{subscription.endpoint_id}"
    end

    def map_status(remote_status)
      case remote_status.to_s
      when "enabled" then :active
      when "onProbation" then :probation
      when "disabledBySystem", "disabledByUser", "disabledBySystemOrUser" then :disabled
      else :error
      end
    end
  end
end
