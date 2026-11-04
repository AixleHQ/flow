# frozen_string_literal: true

require "test_helper"

class Analytics::ClientContractTest < ActiveSupport::TestCase
  METHODS = %i[configured? capture_batch].freeze
  BATCH_URL = "https://us.i.posthog.com/batch/"
  EVENT = { "event" => "project_created", "distinct_id" => "1", "properties" => { "company_id" => 2 },
            "timestamp" => "2026-11-03T10:00:00.000Z", "uuid" => "7f1c" }.freeze

  setup { enable_analytics! }

  test "the fake answers every method the adapter does, with the same arguments" do
    METHODS.each do |name|
      assert_equal Analytics::Client.instance_method(name).parameters, FakeAnalyticsClient.instance_method(name).parameters,
                   "#{name} differs between Analytics::Client and its fake"
    end
  end

  test "posts a batch with the project key to the capture API" do
    request = stub_request(:post, BATCH_URL)
              .with(body: { api_key: "phc_test", batch: [ EVENT ] }.to_json,
                    headers: { "Content-Type" => "application/json" })
              .to_return(status: 200, body: { status: 1 }.to_json)

    assert Analytics::Client.new.capture_batch([ EVENT ])
    assert_requested request
  end

  test "an outage or a refusal is an Analytics::Client::Error" do
    stub_request(:post, BATCH_URL).to_return(status: 503)
    assert_raises(Analytics::Client::Error) { Analytics::Client.new.capture_batch([ EVENT ]) }

    stub_request(:post, BATCH_URL).to_timeout
    assert_raises(Analytics::Client::Error) { Analytics::Client.new.capture_batch([ EVENT ]) }
  end

  test "is not configured without a key" do
    enable_analytics!(api_key: nil)

    assert_not Analytics::Client.new.configured?
  end
end
