# frozen_string_literal: true

# Product analytics in tests. Off unless a test turns it on: the test settings
# are a self-hosted install with no PostHog key, which sends nothing.
#
#   enable_analytics!                       # hosted, key set
#   enable_analytics!(api_key: nil)         # hosted, no key
#   analytics_events                        # what Analytics enqueued, in order
#   analytics_event_names                   # just the names
module AnalyticsTestHelper
  POSTHOG_SETTINGS = { api_key: "phc_test", host: "https://us.i.posthog.com", enable_in_dev: false }.freeze

  def enable_analytics!(mode: Deployment::SAAS, **overrides)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
    Settings.stubs(:posthog).returns(Hashie::Mash.new(POSTHOG_SETTINGS.merge(overrides)))
  end

  def analytics_events
    enqueued_jobs.select { |job| job["job_class"] == "Analytics::CaptureJob" }.map { |job| ActiveJob::Arguments.deserialize(job["arguments"]).first }
  end

  def analytics_event_names = analytics_events.map { |event| event["event"] }

  def analytics_event(name)
    analytics_events.find { |event| event["event"] == name }
  end
end
