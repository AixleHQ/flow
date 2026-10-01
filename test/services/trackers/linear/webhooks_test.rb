# frozen_string_literal: true

require "test_helper"

class Trackers::Linear::WebhooksTest < ActiveSupport::TestCase
  Request = Struct.new(:headers)

  def body(timestamp: (Time.current.to_f * 1000).to_i) = { type: "Issue", webhookTimestamp: timestamp }.to_json

  test "a delivery is authentic when its body is signed with the secret and it was sent within the minute" do
    fresh = body

    assert Trackers::Linear::Webhooks.signed?(Request.new({ "Linear-Signature" => linear_signature(fresh, "s3") }), fresh, "s3")
    assert_not Trackers::Linear::Webhooks.signed?(Request.new({ "Linear-Signature" => linear_signature(fresh, "other") }), fresh, "s3")
    assert_not Trackers::Linear::Webhooks.signed?(Request.new({}), fresh, "s3")
    assert_not Trackers::Linear::Webhooks.signed?(Request.new({ "Linear-Signature" => linear_signature(fresh, "") }), fresh, nil)

    stale = body(timestamp: ((Time.current - 2.minutes).to_f * 1000).to_i)
    assert_not Trackers::Linear::Webhooks.signed?(Request.new({ "Linear-Signature" => linear_signature(stale, "s3") }), stale, "s3")
  end

  test "an app delivery reaches the live OAuth connections to its workspace only" do
    oauth = create(:integration, :linear_oauth, :active)
    app = oauth.tracker_subscriptions.create!(strategy: "app", status: "active")
    key = create(:integration, :linear, :active)
    key.tracker_subscriptions.create!(strategy: "app", status: "active")

    assert_equal [ app ], Trackers::Linear::Webhooks.app_subscriptions({ "organizationId" => FakeLinear::Api::ORGANIZATION })
    assert_empty Trackers::Linear::Webhooks.app_subscriptions({ "organizationId" => "org-other" })
  end
end
