# frozen_string_literal: true

module Trackers
  module Youtrack
    # How a Webhook Triggers delivery proves where it came from: the token the
    # app is configured with, in the header it is configured to send. The app
    # holds one token per YouTrack project, shared by every URL it posts to.
    module Webhooks
      HEADER_NAME = /\A[A-Za-z0-9!#$%&'*+.^_`|~-]+\z/
      MIN_TOKEN = 32
      EVENTS = [ "Issue Created", "Issue Updated", "Comment Added" ].freeze

      module_function

      def authentic?(request, subscription)
        secret = subscription.secret
        presented = request.headers[header(subscription)].to_s
        return false if secret.blank? || presented.blank?

        ActiveSupport::SecurityUtils.secure_compare(presented, secret)
      end

      def header(subscription)
        subscription.settings.to_h["header"].presence || ::Youtrack::Config::DEFAULT_WEBHOOK_HEADER
      end

      def url(subscription)
        subscription.callback_url(::Youtrack::Config.webhook_base_url)
      end
    end
  end
end
