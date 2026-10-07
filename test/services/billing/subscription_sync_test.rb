# frozen_string_literal: true

require "test_helper"

class Billing::SubscriptionSyncTest < ActiveSupport::TestCase
  setup do
    @client = FakeStripeClient.new
  end

  test "a paying company recorded before the period was gets it from Stripe" do
    company = create(:company, :subscribed, billing_period_starts_at: nil, billing_period_ends_at: nil)
    ends = 9.days.from_now.change(usec: 0)
    @client.add_subscription(id: company.stripe_subscription_id, period_end: ends)

    Billing::SubscriptionSync.new(client: @client).call

    assert_equal ends, company.reload.billing_period_ends_at
    assert_equal({ save_default_payment_method: "on_subscription" },
                 @client.subscription_updates.sole[:payment_settings])
  end

  test "a subscription Stripe cannot find is reported, not raised" do
    company = create(:company, :subscribed)

    outcome = Billing::SubscriptionSync.new(client: @client).call

    assert_equal [ [ company.id, "failed: InvalidRequestError: No such subscription: '#{company.stripe_subscription_id}'" ] ],
                 outcome
  end

  test "companies nobody pays for are left alone" do
    create(:company, :trialing)

    assert_empty Billing::SubscriptionSync.new(client: @client).call
  end
end
