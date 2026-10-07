# frozen_string_literal: true

module Trackers
  module Youtrack
    # One `app` subscription per YouTrack project a connection covers: the URL
    # and secret the Aixle Flow app posts that project's events with. The app
    # receives both when its pairing completes and keeps them in the project's
    # settings, so a secret is generated once and kept across ensures.
    class Subscriptions
      def initialize(integration)
        @integration = integration
      end

      def ensure!
        release_dropped!
        project_ids.map { |scope_id| ensure_project!(scope_id) }
      end

      private

      def ensure_project!(scope_id)
        subscription = @integration.tracker_subscriptions.find_or_initialize_by(external_scope_id: scope_id)
        subscription.strategy = "app"
        subscription.status = "pending" if subscription.new_record? || subscription.disabled?
        subscription.secret = SecureRandom.hex(32) if subscription.secret.blank?
        subscription.save! if subscription.changed?
        subscription
      end

      def release_dropped!
        @integration.tracker_subscriptions.live.where.not(external_scope_id: project_ids).find_each do |subscription|
          subscription.update!(status: "disabled")
        end
      end

      def project_ids
        Array(@integration.settings.to_h["youtrack_projects"]).filter_map { |p| p["id"].to_s.presence if p.is_a?(Hash) }
      end
    end
  end
end
