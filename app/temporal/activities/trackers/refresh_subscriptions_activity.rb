# frozen_string_literal: true

module Activities
  module Trackers
    # Daily, from Workflows::TrackerSubscriptionRefreshWorkflow:
    #
    # - extends tracker webhooks that expire (Jira's dynamic webhooks last 30 days);
    # - renews the grant of every Jira 3LO connection idle for 30 days, since
    #   Atlassian retires a refresh token unused for 90.
    #
    # Per-record rescue: one failing connection never stops the rest.
    class RefreshSubscriptionsActivity < ::Activities::Base
      EXPIRY_WINDOW = 7.days
      IDLE_GRANT = 30.days

      def run(_input = nil)
        counts = { refreshed: 0, renewed_grants: 0, errors: 0 }

        TrackerSubscription.expiring(EXPIRY_WINDOW).includes(:integration).find_each do |subscription|
          next unless subscription.integration.active? && subscription.integration.jira?

          ::Trackers::Jira::Subscriptions.new(subscription.integration).refresh!(subscription)
          counts[subscription.reload.failing? ? :errors : :refreshed] += 1
        rescue StandardError => e
          counts[:errors] += 1
          log(:warn, "tracker subscription #{subscription.id} refresh raised: #{e.class}: #{e.message}")
        end

        idle_grants.each do |integration|
          ::Jira::Credential.new(integration).access_token
          counts[:renewed_grants] += 1
        rescue StandardError => e
          counts[:errors] += 1
          log(:warn, "jira integration #{integration.id} grant renewal raised: #{e.class}: #{e.message}")
        end

        log(:info, "tracker subscription sweep: #{counts}")
        counts
      end

      private

      def idle_grants
        Integration.active.where(provider: "jira").where("settings ->> 'auth_mode' = 'oauth'").select do |integration|
          expires_at = integration.credentials_data["expires_at"]
          expires_at.blank? || Time.zone.parse(expires_at) < IDLE_GRANT.ago
        rescue Encryptable::DecryptionError
          false
        end
      end
    end
  end
end
