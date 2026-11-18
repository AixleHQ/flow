# frozen_string_literal: true

module PullRequests
  # Who a code-host connection writes as, for telling Aixle's own reviews and
  # comments apart from people's. The tracker side of the same connection already
  # knows that account (an app's bot, a GitLab service account, the identity an
  # Azure connection learned from its writes), so it answers for both. A
  # connection acting as a person has no account of its own: everything it
  # writes looks like that person's.
  module Identity
    TRACKER_BACKED = %w[github gitlab azure_devops].freeze

    module_function

    def own?(integration, actor)
      provider = tracker_provider(integration)
      provider.present? && provider.own_actor?(actor.to_h.symbolize_keys)
    end

    def mentioned?(integration, text)
      provider = tracker_provider(integration)
      provider.present? && provider.mentions_self?(Trackers.without_code(text.to_s))
    end

    def tracker_provider(integration)
      return unless integration && TRACKER_BACKED.include?(integration.provider.to_s)

      Trackers::Provider.for(integration)
    end
  end
end
