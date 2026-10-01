# frozen_string_literal: true

module Trackers
  module Linear
    # Makes sure a Linear connection's events reach Aixle.
    #
    # The OAuth app's own webhook delivers every workspace that installed it, so
    # an OAuth connection only needs the row its deliveries are recorded on.
    #
    # An API-key connection registers one webhook per team, with a secret of
    # ours, delivered to that subscription's own URL. Linear lets only a
    # workspace admin's key manage webhooks; a refused registration leaves the
    # row failing with the reason, and the next ensure! tries again.
    class Subscriptions
      LABEL = "Aixle"

      # Best effort, for a connection that is gone: Linear disables a webhook
      # that keeps failing anyway.
      def self.release(api_key:, webhook_ids:)
        return if api_key.blank? || webhook_ids.blank?

        api = ::Linear::Api.new(::Linear::Client.new(credential: ::Linear::StaticCredential.api_key(api_key)))
        webhook_ids.each do |id|
          api.delete_webhook(id)
        rescue Trackers::Error => e
          Rails.logger.warn("[Trackers::Linear::Subscriptions] could not remove webhook #{id}: #{e.code}")
        end
      end

      def initialize(integration)
        @integration = integration
      end

      def ensure!
        oauth? ? ensure_app! : ensure_teams!
      end

      private

      def oauth? = @integration.settings.to_h["auth_mode"] == "oauth"

      def ensure_app!
        @integration.tracker_subscriptions.where(strategy: "api").find_each { |s| s.update!(status: "disabled") }
        @integration.tracker_subscriptions.find_or_create_by!(external_scope_id: nil) do |subscription|
          subscription.strategy = "app"
          subscription.status = "active"
        end
      end

      def ensure_teams!
        @integration.tracker_subscriptions.where(strategy: "app").find_each { |s| s.update!(status: "disabled") }
        return [] unless ::Linear::AppConfig.webhooks_enabled?

        release_dropped!
        team_ids.map { |team_id| ensure_team!(team_id) }
      end

      def ensure_team!(team_id)
        subscription = @integration.tracker_subscriptions.find_or_initialize_by(external_scope_id: team_id)
        return subscription if subscription.persisted? && subscription.provider_subscription_id.present? && subscription.status != "disabled"

        subscription.assign_attributes(strategy: "api", status: "pending")
        subscription.secret = SecureRandom.hex(32) if subscription.secret.blank?
        subscription.save!
        id = api.create_webhook(url: subscription.callback_url(::Linear::AppConfig.webhook_base_url), team_id: team_id,
                                secret: subscription.secret, label: LABEL)
        subscription.update!(provider_subscription_id: id, status: "active", last_error: nil)
        subscription
      rescue Trackers::Error => e
        Rails.logger.warn("[Trackers::Linear::Subscriptions] integration #{@integration.id} team #{team_id}: #{e.code}")
        subscription&.update!(status: "failing", last_error: failure_message(e))
        subscription
      end

      def release_dropped!
        @integration.tracker_subscriptions.live.where(strategy: "api").where.not(external_scope_id: team_ids).find_each do |subscription|
          api.delete_webhook(subscription.provider_subscription_id) if subscription.provider_subscription_id.present?
          subscription.update!(status: "disabled")
        rescue Trackers::Error => e
          Rails.logger.warn("[Trackers::Linear::Subscriptions] integration #{@integration.id} could not remove a webhook: #{e.code}")
          subscription.update!(status: "disabled")
        end
      end

      def failure_message(error)
        return error.message.to_s.truncate(250) unless error.code == "permission_denied"

        "Only a Linear workspace admin's API key can register webhooks. Connect with an admin's key, or install Aixle's Linear app."
      end

      def team_ids
        Array(@integration.settings.to_h["linear_teams"]).filter_map { |t| t["id"].to_s.presence if t.is_a?(Hash) }
      end

      def api
        @api ||= ::Linear::Api.for(@integration)
      end
    end
  end
end
