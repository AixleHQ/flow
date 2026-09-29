# frozen_string_literal: true

require "test_helper"

class Billing::Meter::StripeTest < ActiveSupport::TestCase
  setup do
    @client = FakeStripeClient.new
    @adapter = Billing::Meter::Stripe.new(client: @client)
    @hour = Time.utc(2026, 9, 29, 10)
    @acme = create(:company, stripe_customer_id: "cus_acme")
    @globex = create(:company, stripe_customer_id: "cus_globex")
  end

  def report(breakdown)
    CapacityMeterReport.create!(
      provider: "stripe", period_start: @hour,
      quantity_seconds: breakdown.values.sum, breakdown: breakdown, state: "pending"
    )
  end

  test "each company's hour is sent against its own customer, exactly" do
    @adapter.deliver(report(@acme.id.to_s => 5400, @globex.id.to_s => 90))

    assert_equal %w[cus_acme cus_globex], @client.meter_events.map(&:customer_id).sort
    acme_event = @client.meter_events.find { |e| e.customer_id == "cus_acme" }
    assert_equal BigDecimal("90"), acme_event.minutes, "5400 queue-seconds is 90 queue-minutes"
    assert_equal @hour, acme_event.occurred_at
  end

  # Fractions survive: capacity is exact to the second and Stripe takes a decimal,
  # so nothing is rounded on this path.
  test "a fractional minute is sent as one" do
    @adapter.deliver(report(@acme.id.to_s => 90))

    assert_equal BigDecimal("1.5"), @client.meter_events.sole.minutes
  end

  # The ledger replays a failed hour in full. The identifier is what stops the
  # parts that did land from landing twice.
  test "replaying an hour records it once" do
    rows = { @acme.id.to_s => 5400 }
    @adapter.deliver(report(rows))
    CapacityMeterReport.delete_all

    result = @adapter.deliver(report(rows))

    assert_equal 1, @client.meter_events.size
    assert_match(/sent=0:already=1:unbilled=0/, result)
  end

  test "the identifier names the company and the hour" do
    @adapter.deliver(report(@acme.id.to_s => 60))

    assert_equal "capacity:#{@acme.id}:#{@hour.to_i}", @client.meter_events.sole.identifier
  end

  # Ordinary, not exceptional: our own company is `active` because we say so, not
  # because anyone pays us, and it will never have a Stripe customer. It is
  # counted rather than logged, so a permanent condition does not produce a line
  # per company per hour.
  test "a company nobody bills is counted, and the rest are still sent" do
    ours = create(:company)

    result = @adapter.deliver(report(@acme.id.to_s => 60, ours.id.to_s => 60))

    assert_equal [ "cus_acme" ], @client.meter_events.map(&:customer_id)
    assert_match(/sent=1:already=0:unbilled=1/, result)
  end

  test "an hour with nothing billable sends nothing and still answers" do
    assert_match(/sent=0/, @adapter.deliver(report({})))
  end

  # The meter's own loop marks a report failed and replays it, so the adapter has
  # to let a real failure out rather than swallowing it.
  test "a provider failure is not swallowed" do
    @client.failure = "card_declined"

    assert_raises(Billing::StripeClient::Error) { @adapter.deliver(report(@acme.id.to_s => 60)) }
  end
end
