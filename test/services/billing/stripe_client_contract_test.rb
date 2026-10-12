# frozen_string_literal: true

require "test_helper"

# The adapter and its fake have to stay the same shape, or every test below the
# fake is testing something the application does not do.
class Billing::StripeClientContractTest < ActiveSupport::TestCase
  METHODS = %i[
    configured? create_customer create_checkout_session send_meter_event construct_event
    retrieve_subscription adopt_subscription cancel_subscription resume_subscription retrieve_price
    hold_invoice release_invoice issue_invoice metered_minutes
  ].freeze

  test "the fake answers every method the adapter does, with the same arguments" do
    METHODS.each do |name|
      real = Billing::StripeClient.instance_method(name)
      fake = FakeStripeClient.instance_method(name)

      assert_equal real.parameters.map { |kind, key| [ kind, key ] }, fake.parameters.map { |kind, key| [ kind, key ] },
                   "#{name} differs between Billing::StripeClient and its fake"
    end
  end

  test "an unconfigured adapter refuses rather than dialling out" do
    Settings.stubs(:stripe).returns(Hashie::Mash.new(secret_key: nil, price_id: nil))
    client = Billing::StripeClient.new

    assert_not client.configured?
    error = assert_raises(Billing::StripeClient::Error) do
      client.create_customer(company: create(:company), email: "a@b.example")
    end
    assert_match(/not configured/, error.message)
  end

  # An unsigned body is refused before it is read as anything: the URL is not a
  # secret, so the signature is the whole of the authentication.
  test "a webhook is refused without a configured secret" do
    Settings.stubs(:stripe).returns(Hashie::Mash.new(secret_key: "sk_test", price_id: "price", webhook_secret: nil))

    error = assert_raises(Billing::StripeClient::Error) do
      Billing::StripeClient.new.construct_event(payload: "{}", signature: "t=1,v1=deadbeef")
    end
    assert_match(/no webhook secret/, error.message)
  end

  test "a body signed with the wrong secret is refused" do
    Settings.stubs(:stripe).returns(
      Hashie::Mash.new(secret_key: "sk_test", price_id: "price", webhook_secret: "whsec_right")
    )
    payload = { id: "evt_1", type: "checkout.session.completed" }.to_json
    signature = stripe_signature(payload, secret: "whsec_wrong")

    assert_raises(Billing::StripeClient::Error) do
      Billing::StripeClient.new.construct_event(payload: payload, signature: signature)
    end
  end

  test "a body signed with the right secret comes back as an event" do
    Settings.stubs(:stripe).returns(
      Hashie::Mash.new(secret_key: "sk_test", price_id: "price", webhook_secret: "whsec_right")
    )
    payload = { id: "evt_1", type: "checkout.session.completed", data: { object: {} } }.to_json

    event = Billing::StripeClient.new.construct_event(
      payload: payload, signature: stripe_signature(payload, secret: "whsec_right")
    )

    assert_equal "checkout.session.completed", event.type
  end

  # Left on, Stripe converts the checkout page into the visitor's local currency
  # from their IP — a customer in Jakarta was quoted rupiah at Stripe's own rate.
  # That is a second price nobody here set and nobody here can reconcile against
  # the queue-minutes we metered.
  test "a checkout is opened in the price's own currency, never the visitor's" do
    Settings.stubs(:stripe).returns(Hashie::Mash.new(secret_key: "sk_test", price_id: "price_test"))
    captured = nil
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .with { |request| captured = request.body }
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id: "cs_test", object: "checkout.session", url: "https://checkout.test" }.to_json)

    Billing::StripeClient.new.create_checkout_session(
      company: create(:company), customer_id: "cus_1",
      success_url: "https://example.test/ok", cancel_url: "https://example.test/no"
    )

    assert_includes CGI.unescape(captured.to_s), "adaptive_pricing[enabled]=false"
  end

  # At once, with the minutes metered so far invoiced; the reason travels to
  # Stripe's own cancellation analytics as well as ours.
  test "a cancellation ends the subscription now and invoices what was metered, with its reason" do
    Settings.stubs(:stripe).returns(Hashie::Mash.new(secret_key: "sk_test", price_id: "price_test"))
    captured = nil
    stub_request(:delete, %r{\Ahttps://api\.stripe\.com/v1/subscriptions/sub_1})
      .with { |request| captured = CGI.unescape("#{request.uri.query}&#{request.body}") }
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id: "sub_1", object: "subscription", status: "canceled", ended_at: 1_791_000_000 }.to_json)

    subscription = Billing::StripeClient.new.cancel_subscription(subscription_id: "sub_1", reason: "unused", comment: nil)

    assert_includes captured, "invoice_now=true"
    assert_includes captured, "cancellation_details[feedback]=unused"
    assert_not_includes captured, "cancellation_details[comment]"
    assert Billing::SubscriptionState.from(subscription).ended?
  end

  # On an open invoice `auto_advance` is what keeps Stripe retrying the card.
  test "only a draft invoice is held" do
    stub_stripe_settings
    stub_invoice("in_draft", status: "draft")
    stub_invoice("in_open", status: "open")
    held = stub_request(:post, "https://api.stripe.com/v1/invoices/in_draft").with(body: { auto_advance: "false" })
                                                                             .to_return(invoice_body("in_draft", status: "draft"))

    client = Billing::StripeClient.new
    client.hold_invoice(invoice_id: "in_draft")
    client.hold_invoice(invoice_id: "in_open")

    assert_requested held, times: 1
    assert_not_requested :post, "https://api.stripe.com/v1/invoices/in_open"
  end

  # Finalized, Stripe waits another hour before charging unless asked.
  test "issuing a draft finalizes it and charges it now" do
    stub_stripe_settings
    stub_invoice("in_1", status: "draft")
    finalized = stub_request(:post, "https://api.stripe.com/v1/invoices/in_1/finalize")
                .to_return(invoice_body("in_1", status: "open", attempted: false))
    paid = stub_request(:post, "https://api.stripe.com/v1/invoices/in_1/pay")
           .to_return(invoice_body("in_1", status: "paid", attempted: true))

    invoice = Billing::StripeClient.new.issue_invoice(invoice_id: "in_1")

    assert_requested finalized
    assert_requested paid
    assert_equal "paid", invoice.status
  end

  # A decline is the customer's to fix on the hosted page, not a failure to retry.
  test "a declined card leaves the issued invoice open, with its page to pay on" do
    stub_stripe_settings
    stub_request(:get, "https://api.stripe.com/v1/invoices/in_1")
      .to_return(invoice_body("in_1", status: "open", attempted: false))
      .then.to_return(invoice_body("in_1", status: "open", attempted: true))
    stub_request(:post, "https://api.stripe.com/v1/invoices/in_1/pay")
      .to_return(status: 402, headers: { "Content-Type" => "application/json" },
                 body: { error: { type: "card_error", code: "card_declined", message: "Your card was declined." } }.to_json)

    invoice = Billing::StripeClient.new.issue_invoice(invoice_id: "in_1")

    assert_equal "open", invoice.status
    assert_equal "https://invoice.stripe.test/in_1", invoice.hosted_invoice_url
  end

  test "an invoice already charged is not charged again" do
    stub_stripe_settings
    stub_invoice("in_1", status: "open", attempted: true)

    Billing::StripeClient.new.issue_invoice(invoice_id: "in_1")

    assert_not_requested :post, %r{/v1/invoices/in_1/}
  end

  # The meter is the one the price bills, so it is not a second setting.
  test "metered minutes are what the price's meter has counted for the customer" do
    stub_stripe_settings
    stub_request(:get, "https://api.stripe.com/v1/prices/price_test")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id: "price_test", object: "price", recurring: { meter: "mtr_1" } }.to_json)
    from = Time.utc(2026, 10, 12, 14)
    summaries = stub_request(:get, "https://api.stripe.com/v1/billing/meters/mtr_1/event_summaries")
                .with(query: { customer: "cus_1", start_time: from.to_i.to_s, end_time: (from + 1.hour).to_i.to_s })
                .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                           body: { object: "list", has_more: false, data: [
                             { object: "billing.meter_event_summary", aggregated_value: 60.5 },
                             { object: "billing.meter_event_summary", aggregated_value: 20 }
                           ] }.to_json)

    minutes = Billing::StripeClient.new.metered_minutes(customer_id: "cus_1", from: from, to: from + 1.hour)

    assert_requested summaries
    assert_equal BigDecimal("80.5"), minutes
  end

  # Told apart from an outage: an id Stripe does not hold is an ended
  # subscription to a caller, while an unreachable Stripe is "try again".
  test "an id Stripe does not hold is NotFound, not a generic failure" do
    Settings.stubs(:stripe).returns(Hashie::Mash.new(secret_key: "sk_test", price_id: "price_test"))
    stub_request(:get, "https://api.stripe.com/v1/subscriptions/sub_gone")
      .to_return(status: 404, headers: { "Content-Type" => "application/json" },
                 body: { error: { type: "invalid_request_error", code: "resource_missing",
                                  message: "No such subscription: 'sub_gone'" } }.to_json)

    assert_raises(Billing::StripeClient::NotFound) do
      Billing::StripeClient.new.retrieve_subscription(subscription_id: "sub_gone")
    end
  end

  private

  def stub_stripe_settings
    Settings.stubs(:stripe).returns(Hashie::Mash.new(secret_key: "sk_test", price_id: "price_test"))
  end

  def invoice_body(id, status:, attempted: false)
    { status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: id, object: "invoice", status: status, attempted: attempted,
              hosted_invoice_url: status == "draft" ? nil : "https://invoice.stripe.test/#{id}" }.to_json }
  end

  def stub_invoice(id, **attributes)
    stub_request(:get, "https://api.stripe.com/v1/invoices/#{id}").to_return(invoice_body(id, **attributes))
  end

  def stripe_signature(payload, secret:, timestamp: Time.current.to_i)
    digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
    "t=#{timestamp},v1=#{digest}"
  end
end
