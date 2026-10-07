# frozen_string_literal: true

module Trackers
  module Youtrack
    # How a delivery from the Aixle Flow app proves where it came from: the
    # subscription's own secret, which the app keeps in a secret setting of that
    # YouTrack project and sends as is — its rule runtime has no HMAC.
    module Webhooks
      HEADER = "X-Aixle-Token"

      module_function

      def authentic?(request, subscription)
        secret = subscription.secret
        presented = request.headers[HEADER].to_s
        return false if secret.blank? || presented.blank?

        ActiveSupport::SecurityUtils.secure_compare(presented, secret)
      end

      def url(subscription)
        subscription.callback_url(::Youtrack::Config.webhook_base_url)
      end
    end
  end
end
