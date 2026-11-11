# frozen_string_literal: true

require "test_helper"

class Billing::CardPriceTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    @client = FakeStripeClient.new
  end

  def price = Billing::CardPrice.new(client: @client)

  test "a price sold in packs is estimated in whole packs, rounded as the price says" do
    estimate = price.estimate(BigDecimal("130"))

    assert_equal 1000, estimate[:amount_cents]
    assert_equal 60, estimate[:minutes_per_unit]
  end

  # The meter sends fractional minutes and Stripe bills them as sent, so an
  # estimate that floored them would promise less than the invoice.
  test "a price with no pack bills the minutes as the meter sent them" do
    @client.price = { id: "price_fake", object: "price", currency: "usd", unit_amount: 6 }

    estimate = price.estimate(BigDecimal("10.9"))

    assert_equal 65, estimate[:amount_cents]
    assert_equal 1, estimate[:minutes_per_unit]
  end
end
