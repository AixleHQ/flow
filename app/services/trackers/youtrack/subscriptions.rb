# frozen_string_literal: true

module Trackers
  module Youtrack
    # A YouTrack connection's events reach Aixle through the Webhook Triggers
    # app, which a project admin configures by hand in each YouTrack project:
    # one manual subscription per project, with its own URL and the token the
    # app sends. Aixle offers a token of its own; a project whose app already
    # has one (it serves other consumers too) keeps it, and it is entered here.
    class Subscriptions
      def initialize(integration)
        @integration = integration
      end

      def ensure!
        release_dropped!
        project_ids.map { |scope_id| ensure_project!(scope_id) }
      end

      def use_token!(scope_id, token:, header: nil)
        raise Error.new("This connection does not cover that YouTrack project", code: "not_found") unless project_ids.include?(scope_id.to_s)

        header = header.to_s.strip.presence || ::Youtrack::Config::DEFAULT_WEBHOOK_HEADER
        raise Error.new("The header name is not a valid HTTP header name", code: "validation_failed") unless header.match?(Webhooks::HEADER_NAME)
        if token.to_s.strip.length < Webhooks::MIN_TOKEN
          raise Error.new("YouTrack requires a webhook token of at least #{Webhooks::MIN_TOKEN} characters", code: "validation_failed")
        end

        subscription = ensure_project!(scope_id.to_s)
        subscription.secret = token.to_s.strip
        subscription.update!(settings: subscription.settings.to_h.merge("header" => header), status: "pending", last_error: nil)
        subscription
      end

      private

      def ensure_project!(scope_id)
        subscription = @integration.tracker_subscriptions.find_or_initialize_by(external_scope_id: scope_id)
        subscription.strategy = "manual"
        subscription.status = "pending" if subscription.new_record? || subscription.disabled?
        subscription.secret = SecureRandom.hex(32) if subscription.secret.blank?
        subscription.settings = subscription.settings.to_h.reverse_merge("header" => ::Youtrack::Config::DEFAULT_WEBHOOK_HEADER)
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
