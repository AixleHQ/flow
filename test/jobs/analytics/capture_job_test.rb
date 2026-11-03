# frozen_string_literal: true

require "test_helper"

class Analytics::CaptureJobTest < ActiveJob::TestCase
  EVENT = { "event" => "project_created", "distinct_id" => "1", "properties" => {} }.freeze

  setup do
    @client = FakeAnalyticsClient.new
    Analytics::Client.stubs(:new).returns(@client)
  end

  test "sends the event" do
    Analytics::CaptureJob.perform_now(EVENT)

    assert_equal [ [ EVENT ] ], @client.batches
  end

  test "sends nothing once the key is gone" do
    @client.configured = false

    Analytics::CaptureJob.perform_now(EVENT)

    assert_empty @client.batches
  end

  test "an outage is retried a few times, then the event is dropped rather than raised" do
    @client.failure = "PostHog answered 503"

    assert_nothing_raised do
      perform_enqueued_jobs { Analytics::CaptureJob.perform_later(EVENT) }
    end
    assert_empty @client.batches
  end
end
