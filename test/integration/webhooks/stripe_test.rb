# frozen_string_literal: true

require "test_helper"

# The signature is the whole of the authentication here: the URL appears in
# Stripe's dashboard and in delivery logs, so it grants nothing on its own. These
# sign real bodies and let the real adapter verify them — the one path that must
# not be faked.
class Webhooks::StripeTest < ActionDispatch::IntegrationTest
  SECRET = "whsec_test_secret"

  setup do
    Settings.stubs(:stripe).returns(
      Hashie::Mash.new(secret_key: "sk_test", price_id: "price_test", webhook_secret: SECRET)
    )
    @company = create(:company, :trialing, stripe_customer_id: "cus_acme")
  end

  def deliver(type, object, secret: SECRET, signed: true, created: nil)
    event = { id: "evt_#{SecureRandom.hex(4)}", type: type, data: { object: object } }
    event[:created] = created.to_i if created
    payload = event.to_json
    headers = {}
    headers["Stripe-Signature"] = signature_for(payload, secret) if signed
    post stripe_webhook_path, params: payload, headers: headers.merge("CONTENT_TYPE" => "application/json")
  end

  def signature_for(payload, secret, timestamp: Time.current.to_i)
    digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
    "t=#{timestamp},v1=#{digest}"
  end

  # Shaped as the API version our endpoints run on: the period is on the item.
  def subscription_object(id: "sub_1", status: "active", period_start: 10.days.ago, period_end: 20.days.from_now,
                          **over)
    { object: "subscription", id: id, customer: "cus_acme", status: status,
      cancel_at_period_end: false, cancel_at: nil,
      items: { object: "list", data: [ { object: "subscription_item", current_period_start: period_start.to_i,
                                         current_period_end: period_end.to_i } ] } }.merge(over)
  end

  # Since API 2025-03-31 an invoice names its subscription under `parent`.
  def invoice_object(subscription: "sub_1", **over)
    { object: "invoice", id: "in_1", customer: "cus_acme", status: "open",
      hosted_invoice_url: "https://invoice.stripe.test/i/in_1",
      parent: { type: "subscription_details", subscription_details: { subscription: subscription } } }.merge(over)
  end

  def checkout_object(**over)
    { object: "checkout.session", customer: "cus_acme", subscription: "sub_1",
      metadata: { company_id: @company.id.to_s } }.merge(over)
  end

  # ── The signature ─────────────────────────────────────────────────────────

  test "an unsigned body changes nothing" do
    deliver("checkout.session.completed", checkout_object, signed: false)

    assert_response :bad_request
    assert @company.reload.billing_trialing?
  end

  test "a body signed with somebody else's secret changes nothing" do
    deliver("checkout.session.completed", checkout_object, secret: "whsec_not_ours")

    assert_response :bad_request
    assert @company.reload.billing_trialing?
  end

  # ── What the events do ────────────────────────────────────────────────────

  test "a completed checkout is what makes a company paying" do
    deliver("checkout.session.completed", checkout_object)

    assert_response :ok
    assert @company.reload.billing_active?
    assert_equal "sub_1", @company.stripe_subscription_id
  end

  test "a company blocked for spending its allowance starts again on payment" do
    @company.update!(billing_state: "blocked")

    deliver("checkout.session.completed", checkout_object)

    assert @company.reload.billing_active?
  end

  test "a cancelled subscription stops the company" do
    @company.update!(billing_state: "active")

    deliver("customer.subscription.deleted", { object: "subscription", customer: "cus_acme", status: "canceled" })

    assert @company.reload.billing_blocked?
  end

  # `past_due` and `invoice.payment_failed` arrive together in no promised
  # order. Both stop the company, so delivery order cannot flip it back on.
  test "a past-due subscription stops the company for an unpaid invoice" do
    @company.update!(billing_state: "active", stripe_subscription_id: "sub_1")

    deliver("customer.subscription.updated", subscription_object(status: "past_due"))

    assert @company.reload.billing_blocked?
    assert_equal "payment_failed", @company.billing_status
  end

  test "an unpaid subscription stops the company" do
    @company.update!(billing_state: "active")

    deliver("customer.subscription.updated", { object: "subscription", customer: "cus_acme", status: "unpaid",
                                               id: "sub_1" })

    assert @company.reload.billing_blocked?
  end

  # ── The billing period and a scheduled cancellation ──────────────────────

  test "a new subscription records its billing period, read from the item as current API versions put it" do
    starts = Time.zone.parse("2026-10-01 00:00:00")
    ends = Time.zone.parse("2026-11-01 00:00:00")

    deliver("customer.subscription.created", subscription_object(period_start: starts, period_end: ends))

    @company.reload
    assert @company.billing_active?
    assert_equal "sub_1", @company.stripe_subscription_id
    assert_equal starts, @company.billing_period_starts_at
    assert_equal ends, @company.billing_period_ends_at
  end

  test "a cancellation scheduled in Stripe shows as one, and keeps the company running" do
    @company.update!(billing_state: "active", stripe_subscription_id: "sub_1")
    ends = 12.days.from_now.change(usec: 0)

    deliver("customer.subscription.updated",
            subscription_object(period_end: ends, cancel_at_period_end: true, cancel_at: ends.to_i))

    @company.reload
    assert @company.billing_active?
    assert_equal "cancelling", @company.billing_status
    assert_equal ends, @company.billing_cancels_at
  end

  test "a resumed subscription is no longer cancelling" do
    @company.update!(billing_state: "active", stripe_subscription_id: "sub_1", billing_cancels_at: 3.days.from_now)

    deliver("customer.subscription.updated", subscription_object)

    assert_equal "active", @company.reload.billing_status
  end

  # Checkout leaves a subscription `incomplete` for a moment before it is paid.
  # That is not a stop.
  test "an incomplete subscription leaves a trialing company alone" do
    deliver("customer.subscription.created", subscription_object(status: "incomplete"))

    assert @company.reload.billing_trialing?
  end

  test "a subscription that ends stops the company as canceled, on the date it ended" do
    @company.update!(billing_state: "active", stripe_subscription_id: "sub_1", billing_cancels_at: 1.day.ago)
    ended = 1.minute.ago.change(usec: 0)

    deliver("customer.subscription.deleted", subscription_object(status: "canceled", ended_at: ended.to_i))

    @company.reload
    assert_equal "canceled", @company.billing_status
    assert_equal ended, @company.billing_cancels_at
  end

  # A customer who cancelled and came back has two subscriptions behind them. A
  # late event for the old one must not stop the company paying on the new one.
  test "a late end of an earlier subscription does not stop a company that is paying again" do
    @company.update!(billing_state: "active", stripe_subscription_id: "sub_new")

    deliver("customer.subscription.deleted", subscription_object(id: "sub_old", status: "canceled"))
    deliver("invoice.payment_failed", invoice_object(subscription: "sub_old"))

    assert_equal "active", @company.reload.billing_status
  end

  # ── Delivery order ───────────────────────────────────────────────────────

  # Stripe retries a failed delivery for days and promises no order. An update
  # from before the end, arriving after it, must not start the company again.
  test "an update older than the end of the subscription does not bring it back" do
    @company.update!(billing_state: "active", stripe_subscription_id: "sub_1")

    deliver("customer.subscription.deleted", subscription_object(status: "canceled"), created: 1.minute.ago)
    deliver("customer.subscription.updated", subscription_object(cancel_at_period_end: true), created: 1.day.ago)

    assert_equal "canceled", @company.reload.billing_status
  end

  test "an update older than a failed payment does not lift the stop" do
    @company.update!(billing_state: "active", stripe_subscription_id: "sub_1")

    deliver("invoice.payment_failed", invoice_object, created: 1.minute.ago)
    deliver("customer.subscription.updated", subscription_object, created: 1.hour.ago)

    assert_equal "payment_failed", @company.reload.billing_status
  end

  # `past_due` and `invoice.payment_failed` are created together; both apply.
  test "events created in the same second all apply" do
    @company.update!(billing_state: "active", stripe_subscription_id: "sub_1")
    at = 1.minute.ago

    deliver("invoice.payment_failed", invoice_object, created: at)
    deliver("customer.subscription.updated", subscription_object(status: "past_due"), created: at)

    @company.reload
    assert_equal "payment_failed", @company.billing_status
    assert_equal "https://invoice.stripe.test/i/in_1", @company.billing_unpaid_invoice_url
  end

  # ── Failed payments ──────────────────────────────────────────────────────

  test "a failed payment stops the company and keeps the invoice to pay" do
    @company.update!(billing_state: "active", stripe_subscription_id: "sub_1")

    deliver("invoice.payment_failed", invoice_object)

    @company.reload
    assert_equal "payment_failed", @company.billing_status
    assert_equal "https://invoice.stripe.test/i/in_1", @company.billing_unpaid_invoice_url
  end

  test "paying the invoice starts the company again" do
    @company.update!(billing_state: "blocked", billing_block_reason: "payment_failed", stripe_subscription_id: "sub_1",
                     billing_unpaid_invoice_url: "https://invoice.stripe.test/i/in_1")

    deliver("invoice.paid", invoice_object(status: "paid"))

    @company.reload
    assert_equal "active", @company.billing_status
    assert_nil @company.billing_unpaid_invoice_url
  end

  # The final invoice, for the last period's minutes, is Stripe's to chase.
  # Neither its failure nor its payment brings back a subscription that has ended.
  test "the final invoice of an ended subscription neither stops nor restores anything" do
    @company.update!(billing_state: "blocked", billing_block_reason: "canceled", stripe_subscription_id: "sub_1")

    deliver("invoice.payment_failed", invoice_object)
    assert_equal "canceled", @company.reload.billing_status

    deliver("invoice.paid", invoice_object(status: "paid"))
    assert_equal "canceled", @company.reload.billing_status
  end

  # ── What it does not do ───────────────────────────────────────────────────

  # Stripe retries a non-2xx for three days. An event we do not handle will not
  # become one, so it is acknowledged rather than retried.
  test "an event nobody handles is acknowledged" do
    deliver("customer.created", { object: "customer", id: "cus_acme" })

    assert_response :ok
    assert @company.reload.billing_trialing?
  end

  test "an event naming a customer we do not hold is acknowledged and ignored" do
    deliver("checkout.session.completed", { object: "checkout.session", customer: "cus_someone_else",
                                            subscription: "sub_x", metadata: {} })

    assert_response :ok
    assert @company.reload.billing_trialing?
  end

  # A customer made by hand in the dashboard has no id on our side yet; the
  # session still names the company.
  test "a session without a known customer falls back to the company it names" do
    @company.update!(stripe_customer_id: nil)

    deliver("checkout.session.completed", checkout_object(customer: "cus_fresh"))

    assert @company.reload.billing_active?
    assert_equal "cus_fresh", @company.stripe_customer_id
  end
end
