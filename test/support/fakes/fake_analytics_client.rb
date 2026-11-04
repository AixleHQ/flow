# frozen_string_literal: true

# Canonical fake for Analytics::Client, the app's one door to PostHog's capture
# API (docs/testing.md §4, R3). Records every batch instead of sending it, or
# fails like an outage when told to.
#
# Kept interface-identical by test/services/analytics/client_contract_test.rb.
class FakeAnalyticsClient
  attr_reader :batches
  attr_accessor :configured, :failure

  def initialize(configured: true)
    @configured = configured
    @batches = []
  end

  def configured? = @configured

  def capture_batch(events)
    raise Analytics::Client::Error, failure if failure

    batches << events
    true
  end
end
