# frozen_string_literal: true

require "test_helper"

class Trackers::Linear::SubscriptionsTest < ActiveSupport::TestCase
  setup do
    with_linear_oauth_app
    @linear = stub_linear!
  end

  test "an API-key connection registers one signed webhook per team, to each subscription's own URL" do
    integration = create(:integration, :linear, :active)

    subscriptions = Trackers::Linear::Subscriptions.new(integration).ensure!

    assert_equal [ FakeLinear::Api::ENG, FakeLinear::Api::OPS ], subscriptions.map(&:external_scope_id)
    assert(subscriptions.all? { |s| s.status == "active" && s.provider_subscription_id.present? })
    webhook = @linear.webhooks.fetch(subscriptions.first.provider_subscription_id)
    assert_equal [ subscriptions.first.callback_url("https://flow.example.com"), subscriptions.first.secret ], webhook.values_at(:url, :secret)

    Trackers::Linear::Subscriptions.new(integration).ensure!
    assert_equal 2, @linear.calls_to(:create_webhook).size
  end

  test "a key that may not manage webhooks leaves the subscription failing with what to do" do
    integration = create(:integration, :linear, :active, linear_teams: [ { "id" => FakeLinear::Api::ENG, "key" => "ENG" } ])
    @linear.fail_next(:create_webhook, Trackers::Error.new("Forbidden", code: "permission_denied"))

    subscription = Trackers::Linear::Subscriptions.new(integration).ensure!.sole

    assert_equal "failing", subscription.status
    assert_match(/workspace admin's key created with the Admin permission/, subscription.last_error)
  end

  test "a team dropped from the connection has its webhook removed" do
    integration = create(:integration, :linear, :active)
    Trackers::Linear::Subscriptions.new(integration).ensure!
    integration.update!(settings: integration.settings.merge("linear_teams" => [ { "id" => FakeLinear::Api::ENG, "key" => "ENG" } ]))

    Trackers::Linear::Subscriptions.new(integration).ensure!

    assert_equal({ FakeLinear::Api::ENG => "active", FakeLinear::Api::OPS => "disabled" },
                 integration.tracker_subscriptions.pluck(:external_scope_id, :status).to_h)
    assert_equal 1, @linear.webhooks.size
  end

  test "an OAuth connection needs only the row the app's deliveries are recorded on" do
    integration = create(:integration, :linear_oauth, :active)

    subscription = Trackers::Linear::Subscriptions.new(integration).ensure!

    assert_equal [ "app", "active", nil ], [ subscription.strategy.to_s, subscription.status.to_s, subscription.external_scope_id ]
    assert_not @linear.called?(:create_webhook)
  end

  test "removing an API-key connection removes the webhooks it registered" do
    integration = create(:integration, :linear, :active)
    Trackers::Linear::Subscriptions.new(integration).ensure!

    integration.destroy!

    assert_empty @linear.webhooks
  end
end
