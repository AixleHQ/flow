# frozen_string_literal: true

require "test_helper"

class Billing::CancellationSettlementTest < ActiveSupport::TestCase
  setup do
    @client = FakeStripeClient.new
    @company = create(:company, :subscribed, billing_state: "blocked", billing_block_reason: "canceled")
    @client.add_subscription(id: @company.stripe_subscription_id)
    @client.cancel_subscription(subscription_id: @company.stripe_subscription_id, reason: nil, comment: nil)
    @invoice_id = "in_final_#{@company.stripe_subscription_id}"
    @hours = [ Time.utc(2026, 10, 12, 13), Time.utc(2026, 10, 12, 14) ]
    @cancellation = create(:billing_cancellation, company: @company, cancels_at: Time.utc(2026, 10, 12, 14, 20),
                                                  settlement_state: "settling", final_invoice_id: @invoice_id,
                                                  final_usage: { @hours[0].iso8601 => 7200, @hours[1].iso8601 => 2400 })
  end

  def settle = Billing::CancellationSettlement.new(@cancellation, client: @client).call

  def invoice = @client.invoices.fetch(@invoice_id)

  test "every hour is sent, and once Stripe has counted it the invoice is issued and charged" do
    travel_to Time.utc(2026, 10, 12, 14, 21) do
      settle
    end

    assert_equal [ "capacity:#{@company.id}:#{@hours[0].to_i}", "capacity:#{@company.id}:#{@hours[1].to_i}" ],
                 @client.meter_events.map(&:identifier), "the hourly meter's own identifiers, so a repeat is refused"
    assert_equal [ BigDecimal(120), BigDecimal(40) ], @client.meter_events.map(&:minutes)
    assert_equal "paid", invoice[:status]

    @cancellation.reload
    assert_equal "settled", @cancellation.settlement_state
    assert_equal "https://invoice.stripe.test/#{@invoice_id}", @cancellation.final_invoice_url
  end

  # An invoice finalized before Stripe counts an event never bills it.
  test "while Stripe is still counting, the invoice is held and nothing is issued" do
    @client.counting = false

    assert_raises(Billing::CancellationSettlement::NotYetCounted) { settle }

    assert_equal "draft", invoice[:status]
    assert_equal false, invoice[:auto_advance] # rubocop:disable Minitest/RefuteFalse
    assert @cancellation.reload.settling?
  end

  test "a retry sends nothing twice" do
    @client.counting = false
    assert_raises(Billing::CancellationSettlement::NotYetCounted) { settle }
    @client.counting = true

    settle

    assert_equal 2, @client.meter_events.size
    assert_equal "settled", @cancellation.reload.settlement_state
  end

  test "a declined card still settles: the invoice stays open to pay" do
    @client.card_declines = true

    settle

    assert_equal "open", invoice[:status]
    assert invoice[:attempted]
    assert_equal "settled", @cancellation.reload.settlement_state
  end

  test "with nothing used, the invoice is issued without sending anything" do
    @cancellation.update!(final_usage: {})

    settle

    assert_empty @client.meter_events
    assert_equal "settled", @cancellation.reload.settlement_state
  end

  # A handover to AWS Marketplace records the cancellation before Stripe is
  # told, so the subscription is stopped from here and the rest follows.
  test "a cancellation Stripe has not heard of stops the subscription first, then settles" do
    @client.add_subscription(id: "sub_card")
    @cancellation.update!(settlement_state: "cancelling", stripe_subscription_id: "sub_card",
                          final_invoice_id: nil, cancels_at: Time.utc(2026, 10, 12, 14, 20))

    travel_to Time.utc(2026, 10, 12, 14, 21) do
      settle
    end

    assert_equal "canceled", @client.subscriptions.fetch("sub_card")[:status]
    @cancellation.reload
    assert_equal "settled", @cancellation.settlement_state
    assert_equal "in_final_sub_card", @cancellation.final_invoice_id
    assert_equal Time.utc(2026, 10, 12, 14, 21), @cancellation.cancels_at
    assert_equal "paid", @client.invoices.fetch("in_final_sub_card")[:status]
  end

  # A cancel that landed at Stripe but was not recorded here is not sent again:
  # Stripe refuses to cancel a cancelled subscription, and a retry that did
  # would fail for ever.
  test "a subscription already stopped at Stripe is read, not stopped again" do
    @client.add_subscription(id: "sub_card")
    @client.cancel_subscription(subscription_id: "sub_card", reason: nil, comment: nil)
    @cancellation.update!(settlement_state: "cancelling", stripe_subscription_id: "sub_card", final_invoice_id: nil)
    updates_before = @client.subscription_updates.size

    settle

    assert_equal updates_before, @client.subscription_updates.size
    assert_equal "in_final_sub_card", @cancellation.reload.final_invoice_id
    assert_equal "settled", @cancellation.settlement_state
  end

  test "a subscription Stripe cannot be asked about is still to be stopped" do
    @client.add_subscription(id: "sub_card")
    @cancellation.update!(settlement_state: "cancelling", stripe_subscription_id: "sub_card", final_invoice_id: nil)
    @client.failure = "unreachable"

    assert_raises(Billing::StripeClient::Error) { settle }

    assert @cancellation.reload.cancelling?
    assert_equal "active", @client.subscriptions.fetch("sub_card")[:status]
  end

  test "a settlement that is done is not done again" do
    @cancellation.update!(settlement_state: "settled")

    settle

    assert_empty @client.meter_events
    assert_equal "draft", invoice[:status]
  end

  # Held forever, the invoice would bill nothing at all.
  test "given up on, the invoice goes back to Stripe to finalize on its own" do
    @client.hold_invoice(invoice_id: @invoice_id)

    Billing::CancellationSettlement.new(@cancellation, client: @client).release!(StandardError.new("Stripe is down"))

    assert invoice[:auto_advance]
    @cancellation.reload
    assert_equal "failed", @cancellation.settlement_state
    assert_equal "Stripe is down", @cancellation.settlement_error
  end
end
