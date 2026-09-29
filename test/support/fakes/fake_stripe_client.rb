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

  attr_reader :customers, :checkout_sessions, :meter_events
  attr_accessor :configured, :failure, :checkout_url

  def initialize(configured: true)
    @configured = configured
    @customers = []
    @checkout_sessions = []
    @meter_events = []
    @checkout_url = "https://checkout.stripe.test/session"
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

  def construct_event(payload:, signature:)
    raise_failure!
    raise Billing::StripeClient::Error, "no signature" if signature.blank?

    ::Stripe::Event.construct_from(JSON.parse(payload, symbolize_names: true))
  end

  private

  def raise_failure!
    raise Billing::StripeClient::Error, failure if failure
  end
end
