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

  def deliver(type, object, secret: SECRET, signed: true)
    payload = { id: "evt_#{SecureRandom.hex(4)}", type: type, data: { object: object } }.to_json
    headers = {}
    headers["Stripe-Signature"] = signature_for(payload, secret) if signed
    post stripe_webhook_path, params: payload, headers: headers.merge("CONTENT_TYPE" => "application/json")
  end

  def signature_for(payload, secret, timestamp: Time.current.to_i)
    digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
    "t=#{timestamp},v1=#{digest}"
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

  # A failed payment starts a dunning cycle that usually ends in payment, so the
  # customer is carried rather than stopped on the first retry.
  test "a past-due subscription keeps running" do
    @company.update!(billing_state: "active")

    deliver("customer.subscription.updated", { object: "subscription", customer: "cus_acme", status: "past_due",
                                               id: "sub_1" })

    assert @company.reload.billing_active?
  end

  test "an unpaid subscription stops the company" do
    @company.update!(billing_state: "active")

    deliver("customer.subscription.updated", { object: "subscription", customer: "cus_acme", status: "unpaid",
                                               id: "sub_1" })

    assert @company.reload.billing_blocked?
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
