# frozen_string_literal: true

require "test_helper"

# The adapter and its fake have to stay the same shape, or every test below the
# fake is testing something the application does not do.
class Billing::StripeClientContractTest < ActiveSupport::TestCase
  METHODS = %i[
    configured? create_customer create_checkout_session send_meter_event construct_event
    retrieve_subscription adopt_subscription schedule_cancellation resume_subscription retrieve_price
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

  # Never sooner than the period's end, so the minutes metered up to it are
  # invoiced on that period's own invoice; the reason travels to Stripe's own
  # cancellation analytics as well as ours.
  test "a cancellation is scheduled for the period's end, with its reason" do
    Settings.stubs(:stripe).returns(Hashie::Mash.new(secret_key: "sk_test", price_id: "price_test"))
    captured = nil
    stub_request(:post, "https://api.stripe.com/v1/subscriptions/sub_1")
      .with { |request| captured = CGI.unescape(request.body.to_s) }
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id: "sub_1", object: "subscription", status: "active", cancel_at_period_end: true }.to_json)

    Billing::StripeClient.new.schedule_cancellation(subscription_id: "sub_1", reason: "unused", comment: nil)

    assert_includes captured, "cancel_at_period_end=true"
    assert_includes captured, "cancellation_details[feedback]=unused"
    assert_not_includes captured, "cancellation_details[comment]"
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

  def stripe_signature(payload, secret:, timestamp: Time.current.to_i)
    digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
    "t=#{timestamp},v1=#{digest}"
  end
end
