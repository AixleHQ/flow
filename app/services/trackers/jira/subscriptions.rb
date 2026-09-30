# frozen_string_literal: true

module Trackers
  module Jira
    # Makes sure a Jira connection's events reach /webhooks/trackers.
    #
    # A service-account connection cannot register webhooks — Atlassian lets only
    # apps do that — so it gets a manual subscription: an endpoint URL and a
    # secret for a Jira admin to enter as a system webhook.
    #
    # A 3LO connection registers one dynamic webhook for its projects. Those
    # expire after 30 days (refreshed daily by TrackerSubscriptionRefreshWorkflow),
    # and Atlassian allows five per app, user and site, so webhooks this app left
    # behind are deleted before a new one is registered.
    class Subscriptions
      LIFETIME = 30.days

      def initialize(integration)
        @integration = integration
      end

      def ensure!
        return manual! if service_account?
        return unless ::Jira::AppConfig.webhooks_enabled?

        subscription = connection_subscription(strategy: "api")
        return subscription if current?(subscription)

        register!(subscription)
      end

      def refresh!(subscription)
        expires_at = api.refresh_webhooks([ subscription.provider_subscription_id ])
        subscription.update!(expires_at: expires_at || LIFETIME.from_now, status: "active", last_error: nil)
      rescue ::Jira::Error => e
        return register!(subscription) if e.code == "not_found"

        failed!(subscription, e)
      end

      private

      def service_account? = @integration.settings.to_h["auth_mode"] == "service_account"

      def manual!
        connection_subscription(strategy: "manual").tap do |subscription|
          subscription.update!(secret: SecureRandom.hex(32)) if subscription.secret.blank?
        end
      end

      def connection_subscription(strategy:)
        @integration.tracker_subscriptions.find_or_create_by!(external_scope_id: nil) { |s| s.strategy = strategy }
      end

      def current?(subscription)
        subscription.provider_subscription_id.present? && subscription.settings["jql"] == jql &&
          subscription.expires_at.present? && subscription.expires_at > 1.day.from_now
      end

      def register!(subscription)
        return subscription if project_ids.empty?

        release!(subscription)
        id = api.register_webhook(url: Webhooks.app_url, jql: jql, events: Webhooks::EVENTS)
        subscription.update!(provider_subscription_id: id, settings: { "jql" => jql }, expires_at: LIFETIME.from_now,
                             status: "active", last_error: nil)
        subscription
      rescue ::Jira::Error => e
        failed!(subscription, e)
      end

      # This subscription's previous webhook, and any other this app registered
      # on the site that no live subscription holds any more.
      def release!(subscription)
        held = TrackerSubscription.live.where(strategy: "api").where.not(id: subscription.id)
                                  .joins(:integration).where(integrations: { provider: "jira" })
                                  .where("integrations.settings ->> 'cloud_id' = ?", cloud_id)
                                  .pluck(:provider_subscription_id).compact.to_set
        stale = api.webhooks.map { |w| w[:id] }.reject { |id| held.include?(id) }
        api.delete_webhooks(stale)
      rescue ::Jira::Error => e
        Rails.logger.warn("[Trackers::Jira::Subscriptions] integration #{@integration.id} could not release webhooks: #{e.code}")
      end

      def failed!(subscription, error)
        Rails.logger.warn("[Trackers::Jira::Subscriptions] integration #{@integration.id}: #{error.code} #{error.message}")
        subscription.update!(status: "failing", last_error: error.message.to_s.truncate(250))
        subscription
      end

      def jql
        "project IN (#{project_ids.join(', ')})"
      end

      def project_ids
        Array(@integration.settings.to_h["jira_projects"]).filter_map { |p| p["id"].to_s.presence if p.is_a?(Hash) }
                                                         .select { |id| id.match?(/\A\d+\z/) }.sort
      end

      def cloud_id = @integration.settings.to_h["cloud_id"].to_s

      def api
        @api ||= ::Jira::Api.for(@integration)
      end
    end
  end
end
