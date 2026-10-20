# frozen_string_literal: true

module Trackers
  module Gitlab
    # One project hook per tracked GitLab project, delivered to that
    # subscription's own URL and authenticated by its secret in
    # `X-Gitlab-Token` (docs/design/gitlab-tracker.md §5). Registering one takes
    # the Maintainer role; a refused registration leaves the row failing with
    # the reason, and the next ensure! tries again.
    class Subscriptions
      # Best effort, for a connection that is gone.
      def self.release(token:, hooks:)
        return if token.blank? || hooks.blank?

        api = ::Gitlab::TrackerApi.new(::Gitlab::Rest.new(token: token))
        hooks.each do |project_id, hook_id|
          api.delete_hook(project_id, hook_id)
        rescue Trackers::Error => e
          Rails.logger.warn("[Trackers::Gitlab::Subscriptions] could not remove hook #{hook_id}: #{e.code}")
        end
      end

      def initialize(integration)
        @integration = integration
      end

      def ensure!
        return [] unless ::Gitlab::AppConfig.webhooks_enabled?

        release_dropped!
        project_ids.map { |project_id| ensure_project!(project_id) }
      end

      private

      def ensure_project!(project_id)
        subscription = @integration.tracker_subscriptions.find_or_initialize_by(external_scope_id: project_id)
        return subscription if subscription.persisted? && subscription.provider_subscription_id.present? && subscription.status != "disabled"

        subscription.assign_attributes(strategy: "api", status: "pending")
        subscription.secret = SecureRandom.hex(32) if subscription.secret.blank?
        subscription.save!
        id = api.create_hook(project_id, url: subscription.callback_url(::Gitlab::AppConfig.webhook_base_url), token: subscription.secret)
        subscription.update!(provider_subscription_id: id, status: "active", last_error: nil)
        subscription
      rescue Trackers::Error => e
        Rails.logger.warn("[Trackers::Gitlab::Subscriptions] integration #{@integration.id} project #{project_id}: #{e.code}")
        subscription&.update!(status: "failing", last_error: failure_message(e))
        subscription
      end

      def release_dropped!
        @integration.tracker_subscriptions.live.where(strategy: "api").where.not(external_scope_id: project_ids).find_each do |subscription|
          api.delete_hook(subscription.external_scope_id, subscription.provider_subscription_id) if subscription.provider_subscription_id.present?
          subscription.update!(status: "disabled")
        rescue Trackers::Error => e
          Rails.logger.warn("[Trackers::Gitlab::Subscriptions] integration #{@integration.id} could not remove a hook: #{e.code}")
          subscription.update!(status: "disabled")
        end
      end

      def failure_message(error)
        return error.message.to_s.truncate(250) unless %w[permission_denied not_found].include?(error.code)

        "GitLab did not let this connection add a webhook to the project: it takes the Maintainer role there."
      end

      def project_ids
        Array(@integration.settings.to_h["gitlab_trackers"]).filter_map { |t| t["id"].to_s.presence if t.is_a?(Hash) }
      end

      def api
        @api ||= ::Gitlab::TrackerApi.for(@integration)
      end
    end
  end
end
