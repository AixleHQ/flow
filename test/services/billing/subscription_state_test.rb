# frozen_string_literal: true

require "test_helper"

class Billing::SubscriptionStateTest < ActiveSupport::TestCase
  PERIOD_START = Time.zone.parse("2026-10-01 00:00")
  PERIOD_END = Time.zone.parse("2026-11-01 00:00")

  def subscription(**fields)
    ::Stripe::Subscription.construct_from({ id: "sub_1", object: "subscription", status: "active" }.merge(fields))
  end

  # API 2025-03-31 and later: the period is on the item.
  test "it reads the billing period off the item" do
    state = Billing::SubscriptionState.from(subscription(
      items: { data: [ { current_period_start: PERIOD_START.to_i, current_period_end: PERIOD_END.to_i } ] }
    ))

    assert_equal PERIOD_START, state.period_starts_at
    assert_equal PERIOD_END, state.period_ends_at
  end

  # Before it: on the subscription. Webhook payloads follow the endpoint's version.
  test "it reads the billing period off an older subscription too" do
    state = Billing::SubscriptionState.from(subscription(current_period_start: PERIOD_START.to_i,
                                                         current_period_end: PERIOD_END.to_i))

    assert_equal PERIOD_END, state.period_ends_at
  end

  test "a cancellation at the period's end is dated to it" do
    state = Billing::SubscriptionState.from(subscription(
      cancel_at_period_end: true,
      items: { data: [ { current_period_start: PERIOD_START.to_i, current_period_end: PERIOD_END.to_i } ] }
    ))

    assert_equal PERIOD_END, state.cancels_at
  end

  test "it sorts Stripe's statuses into running, unpaid and ended" do
    assert Billing::SubscriptionState.from(subscription(status: "trialing")).running?
    assert Billing::SubscriptionState.from(subscription(status: "past_due")).unpaid?
    assert Billing::SubscriptionState.from(subscription(status: "incomplete_expired")).ended?

    incomplete = Billing::SubscriptionState.from(subscription(status: "incomplete"))
    assert_not incomplete.running? || incomplete.unpaid? || incomplete.ended?
  end
end
