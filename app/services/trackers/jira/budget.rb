# frozen_string_literal: true

module Trackers
  module Jira
    # Atlassian gives a 3LO app one hourly rate-limit pool shared by every site
    # that installed it (docs/design/tracker-attachments.md §10.1): one
    # customer's bulk work can exhaust it for all of them. So work nobody is
    # waiting on — copying an issue's files when a run starts — takes at most a
    # fixed share per connection per hour, and stops while Atlassian reports the
    # pool near its limit. An agent's own calls are never held back here.
    module Budget
      JOB_SHARE_PER_HOUR = 300

      module_function

      # A service account authenticates as itself, not through the app, so its
      # traffic is kept apart until it is known which pool Atlassian counts it in.
      def pool_for(integration)
        integration.settings.to_h["auth_mode"] == "service_account" ? "jira:service_account:#{integration.id}" : "jira:app"
      end

      # Every response reports the pool's state; the latest one wins.
      def observe(pool, headers)
        remaining = headers["x-ratelimit-remaining"]
        near = headers["x-ratelimit-nearlimit"]
        return if remaining.nil? && near.nil?

        Rails.cache.write(state_key(pool), { "remaining" => remaining&.to_i, "near_limit" => near.to_s == "true",
                                             "at" => Time.current.iso8601 }, expires_in: 1.hour)
      end

      def state(pool) = Rails.cache.read(state_key(pool))

      def near_limit?(pool) = state(pool).to_h["near_limit"] == true

      # Takes `count` from the connection's share of this hour; false when it is spent.
      def take(integration, count = 1)
        key = [ "trackers", "jira_budget", integration.id, Time.current.utc.beginning_of_hour.to_i ]
        used = Rails.cache.increment(key, count, expires_in: 2.hours)
        used.nil? || used <= JOB_SHARE_PER_HOUR
      end

      def state_key(pool) = [ "trackers", "jira_rate_limit", pool ]
    end
  end
end
