# frozen_string_literal: true

require "test_helper"

class TrackerSubscriptionTest < ActiveSupport::TestCase
  test "an endpoint token is minted once, and the secret is kept encrypted" do
    subscription = create(:tracker_subscription, secret: "s3cret")

    assert_match(/\A[\w-]{32}\z/, subscription.endpoint_token)
    assert_not_includes subscription.encrypted_secret, "s3cret"
    assert_equal "s3cret", TrackerSubscription.find(subscription.id).secret
    assert_equal "https://hooks.example.com/webhooks/trackers/#{subscription.endpoint_token}",
                 subscription.callback_url("https://hooks.example.com/")
  end

  test "one subscription per connection and external scope, a connection-wide one included" do
    subscription = create(:tracker_subscription)

    duplicate = build(:tracker_subscription, integration: subscription.integration)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save! }
  end

  test "expiring lists live dynamic subscriptions due within the window" do
    integration = create(:integration, :jira_oauth, :active)
    due = create(:tracker_subscription, integration: integration, strategy: "api", expires_at: 2.days.from_now)
    create(:tracker_subscription, integration: integration, external_scope_id: "x", strategy: "api", expires_at: 2.days.from_now,
                                  status: "disabled")
    create(:tracker_subscription, integration: integration, external_scope_id: "y", strategy: "manual", expires_at: 2.days.from_now)

    assert_equal [ due ], TrackerSubscription.expiring(7.days).to_a
  end
end

class TrackerDeliveryTest < ActiveSupport::TestCase
  test "a redelivery of the same event is recorded once, and its notifications come back as they went in" do
    subscription = create(:tracker_subscription)
    notification = Trackers::Notification.build(kind: :issue_updated, scope_id: "10000", issue_id: "1", revision: "2",
                                                changes: [ { field: "status", from: "A", to: "B", to_id: "3" } ], actor: { id: "a" })

    first = TrackerDelivery.record(subscription: subscription, dedup_key: "d-1", notifications: [ notification ])
    again = TrackerDelivery.record(subscription: subscription, dedup_key: "d-1", notifications: [ notification ])

    assert_nil again
    assert_equal [ notification ], first.reload.notification_objects
  end
end
