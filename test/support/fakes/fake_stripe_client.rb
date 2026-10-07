# frozen_string_literal: true

# Canonical fake for Billing::StripeClient. Never stub ::Stripe directly
# (docs/testing.md §4, R2/R3): this application talks to Stripe through one
# adapter, and the tests below it drive this.
#
#   client = FakeStripeClient.new
#   client.send_meter_event(...)            # => recorded in #meter_events
#   client.send_meter_event(same identifier) # => :duplicate, as Stripe answers
#
# Kept interface-identical by
# test/services/billing/stripe_client_contract_test.rb.
class FakeStripeClient
  Customer = Struct.new(:id, :email, :name, keyword_init: true)
  CheckoutSession = Struct.new(:id, :url, :customer, keyword_init: true)
  MeterEvent = Struct.new(:identifier, :customer_id, :minutes, :occurred_at, keyword_init: true)

  attr_reader :customers, :checkout_sessions, :meter_events, :subscriptions, :subscription_updates
  attr_accessor :configured, :failure, :checkout_url, :price

  def initialize(configured: true)
    @configured = configured
    @customers = []
    @checkout_sessions = []
    @meter_events = []
    @subscriptions = {}
    @subscription_updates = []
    @checkout_url = "https://checkout.stripe.test/session"
    @price = { id: "price_fake", object: "price", currency: "usd", unit_amount: 500,
               transform_quantity: { divide_by: 60, round: "down" } }
  end

  # Shaped as API 2025-03-31 and later shape it: the billing period lives on the
  # item, not on the subscription.
  def add_subscription(id:, status: "active", period_start: 10.days.ago, period_end: 20.days.from_now, **extra)
    @subscriptions[id] = {
      id: id, object: "subscription", status: status, cancel_at_period_end: false, cancel_at: nil,
      items: { object: "list", data: [ { object: "subscription_item",
                                         current_period_start: period_start.to_i,
                                         current_period_end: period_end.to_i } ] }
    }.merge(extra)
  end

  def configured? = @configured

  def create_customer(company:, email:)
    raise_failure!
    Customer.new(id: "cus_fake_#{company.id}", email: email, name: company.name).tap { |c| @customers << c }
  end

  def create_checkout_session(company:, customer_id:, success_url:, cancel_url:)
    raise_failure!
    session = CheckoutSession.new(id: "cs_fake_#{company.id}", url: checkout_url, customer: customer_id)
    @checkout_sessions << { session: session, success_url: success_url, cancel_url: cancel_url }
    session
  end

  # What the adapter sends, for the assertions that care about the shape rather
  # than the result.
  def last_checkout_arguments = @checkout_sessions.last

  # The identifier is what makes a replayed hour land once, so the fake answers a
  # repeat the way Stripe does rather than recording it twice.
  def send_meter_event(customer_id:, minutes:, occurred_at:, identifier:)
    raise_failure!
    return :duplicate if @meter_events.any? { |event| event.identifier == identifier }

    MeterEvent.new(
      identifier: identifier, customer_id: customer_id, minutes: minutes, occurred_at: occurred_at
    ).tap { |event| @meter_events << event }
  end

  def retrieve_subscription(subscription_id:)
    raise_failure!
    subscription!(subscription_id)
  end

  def adopt_subscription(subscription_id:)
    update_subscription(subscription_id, payment_settings: { save_default_payment_method: "on_subscription" })
  end

  def schedule_cancellation(subscription_id:, reason:, comment:)
    period_end = subscription!(subscription_id).items.data.first.current_period_end
    update_subscription(subscription_id, cancel_at_period_end: true, cancel_at: period_end,
                                         cancellation_details: { feedback: reason, comment: comment })
  end

  def resume_subscription(subscription_id:)
    update_subscription(subscription_id, cancel_at_period_end: false, cancel_at: nil)
  end

  def retrieve_price
    raise_failure!
    ::Stripe::Price.construct_from(price)
  end

  def construct_event(payload:, signature:)
    raise_failure!
    raise Billing::StripeClient::Error, "no signature" if signature.blank?

    ::Stripe::Event.construct_from(JSON.parse(payload, symbolize_names: true))
  end

  private

  # Stripe answers an id it does not hold with an InvalidRequestError, which the
  # adapter turns into its own error.
  def subscription!(id)
    data = @subscriptions[id]
    raise Billing::StripeClient::NotFound, "InvalidRequestError: No such subscription: '#{id}'" if data.nil?

    ::Stripe::Subscription.construct_from(data)
  end

  def update_subscription(id, **changes)
    raise_failure!
    subscription!(id)
    @subscription_updates << { id: id, **changes }
    @subscriptions[id] = @subscriptions[id].merge(changes)
    subscription!(id)
  end

  def raise_failure!
    raise Billing::StripeClient::Error, failure if failure
  end
end
