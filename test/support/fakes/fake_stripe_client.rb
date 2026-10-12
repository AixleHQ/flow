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

  attr_reader :customers, :checkout_sessions, :meter_events, :subscriptions, :subscription_updates, :invoices
  # `counting` false is Stripe still counting what it was sent: the meter
  # answers zero. `card_declines` makes paying an invoice leave it open.
  attr_accessor :configured, :failure, :checkout_url, :price, :counting, :card_declines

  def initialize(configured: true)
    @configured = configured
    @customers = []
    @checkout_sessions = []
    @meter_events = []
    @subscriptions = {}
    @subscription_updates = []
    @invoices = {}
    @counting = true
    @card_declines = false
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

  # As Stripe does with `invoice_now`: the final invoice starts as a draft.
  def cancel_subscription(subscription_id:, reason:, comment:)
    invoice_id = "in_final_#{subscription_id}"
    canceled = update_subscription(subscription_id, status: "canceled", ended_at: Time.current.to_i,
                                                    cancellation_details: { feedback: reason, comment: comment },
                                                    latest_invoice: invoice_id)
    @invoices[invoice_id] = { id: invoice_id, object: "invoice", status: "draft", auto_advance: true,
                              attempted: false, hosted_invoice_url: nil }
    canceled
  end

  def hold_invoice(invoice_id:)
    draft_only(invoice_id) { update_invoice(invoice_id, auto_advance: false) }
  end

  def release_invoice(invoice_id:)
    draft_only(invoice_id) { update_invoice(invoice_id, auto_advance: true) }
  end

  def issue_invoice(invoice_id:)
    raise_failure!
    invoice!(invoice_id)
    if @invoices[invoice_id][:status] == "draft"
      update_invoice(invoice_id, status: "open", auto_advance: true,
                                 hosted_invoice_url: "https://invoice.stripe.test/#{invoice_id}")
    end
    return invoice!(invoice_id) unless @invoices[invoice_id][:status] == "open" && !@invoices[invoice_id][:attempted]

    update_invoice(invoice_id, attempted: true, status: card_declines ? "open" : "paid")
  end

  def metered_minutes(customer_id:, from:, to:)
    raise_failure!
    return BigDecimal(0) unless counting

    @meter_events.select { |event| event.customer_id == customer_id && event.occurred_at >= from && event.occurred_at < to }
                 .sum(BigDecimal(0)) { |event| BigDecimal(event.minutes.to_s) }
  end

  def add_invoice(id:, **attributes)
    @invoices[id] = { id: id, object: "invoice", status: "draft", auto_advance: true, attempted: false,
                      hosted_invoice_url: nil }.merge(attributes)
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

  def invoice!(id)
    data = @invoices[id]
    raise Billing::StripeClient::NotFound, "InvalidRequestError: No such invoice: '#{id}'" if data.nil?

    ::Stripe::Invoice.construct_from(data)
  end

  def update_invoice(id, **changes)
    @invoices[id] = @invoices[id].merge(changes)
    invoice!(id)
  end

  def draft_only(id)
    raise_failure!
    invoice!(id)
    @invoices[id][:status] == "draft" ? yield : invoice!(id)
  end

  def raise_failure!
    raise Billing::StripeClient::Error, failure if failure
  end
end
