# frozen_string_literal: true

module Trackers
  module Linear
    # How a Linear webhook proves where it came from: `Linear-Signature`, the
    # hex HMAC-SHA256 of the body, and a `webhookTimestamp` within a minute, so
    # a captured delivery cannot be replayed later.
    #
    # An API-key connection's webhooks are ours, one per team, signed with each
    # subscription's secret. The OAuth app's webhook is Linear's, one URL for
    # every workspace that installed the app, signed with the app's secret and
    # routed by the workspace it names.
    module Webhooks
      APP_PATH = "/webhooks/trackers/app/linear"
      TOLERANCE = 60.seconds

      module_function

      def signed?(request, raw_body, secret)
        signature = request.headers["Linear-Signature"].to_s
        return false if secret.blank? || signature.blank?
        return false unless ActiveSupport::SecurityUtils.secure_compare(OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body),
                                                                        signature.downcase)

        recent?(raw_body)
      end

      def app_signed?(request, raw_body)
        signed?(request, raw_body, ::Linear::AppConfig.app_webhook_secret)
      end

      def recent?(raw_body)
        timestamp = JSON.parse(raw_body)["webhookTimestamp"].to_i
        timestamp.positive? && ((Time.current.to_f * 1000) - timestamp).abs <= TOLERANCE.in_milliseconds
      rescue JSON::ParserError
        false
      end

      def app_url
        "#{::Linear::AppConfig.webhook_base_url.chomp('/')}#{APP_PATH}"
      end

      # The live app subscriptions of the OAuth connections to the payload's workspace.
      def app_subscriptions(payload)
        organization = payload["organizationId"].to_s
        return [] if organization.blank?

        TrackerSubscription.live.where(strategy: "app", external_scope_id: nil)
                           .joins(:integration).where(integrations: { provider: "linear" })
                           .where("integrations.settings ->> 'organization_id' = ?", organization)
                           .where("integrations.settings ->> 'auth_mode' = 'oauth'")
                           .includes(:integration).to_a
      end
    end
  end
end
