# frozen_string_literal: true

# Stripe's account of what happened to a subscription.
#
# The only thing that moves a company from `trialing`/`blocked` to `active`
# without a platform administrator: paying is a fact Stripe owns, and asking it
# on every page load would be a call per request against an API with a rate
# limit.
#
# THE SIGNATURE IS THE AUTHENTICATION. The URL is not a secret — it appears in
# Stripe's own dashboard and in delivery logs — so a body that is not signed with
# this endpoint's secret is refused before it is read as anything. Without a
# configured secret nothing is accepted at all, which is the right default for an
# endpoint that grants paid status.
class Webhooks::StripeController < ActionController::API
  # Stripe retries a non-2xx for up to three days. Anything that will not succeed
  # on a retry — an event we do not handle, a company that no longer exists — is
  # acknowledged rather than retried forever.
  MAX_PAYLOAD_BYTES = 512 * 1024

  HANDLED = %w[
    checkout.session.completed
    customer.subscription.created
    customer.subscription.updated
    customer.subscription.deleted
    invoice.payment_failed
    invoice.paid
  ].freeze

  before_action :enforce_payload_limit

  def receive
    event = client.construct_event(payload: request.raw_post, signature: request.headers["Stripe-Signature"])
    return head(:ok) unless HANDLED.include?(event.type)

    handle(event)
    head :ok
  rescue Billing::StripeClient::Error => e
    # Refused, not retried: a body we cannot verify will not verify later either.
    Rails.logger.warn("[Webhooks::Stripe] refused: #{e.message}")
    head :bad_request
  end

  private

  def handle(event)
    object = event.data.object
    company = company_for(object)
    return Rails.logger.info("[Webhooks::Stripe] #{event.type} names no company we hold") if company.nil?

    @event_at = event.try(:created) && Time.zone.at(event.created)
    return ignore(company, "#{event.type} #{event.id}, older than the last event applied") if stale?(company)

    case event.type
    when "checkout.session.completed" then activate(company, object)
    when "customer.subscription.created", "customer.subscription.updated"
      follow(company, Billing::SubscriptionState.from(object))
    when "customer.subscription.deleted" then ended(company, Billing::SubscriptionState.from(object))
    when "invoice.payment_failed" then payment_failed(company, object)
    when "invoice.paid" then paid(company, object)
    end
  end

  # By the customer id we stored when the checkout was opened, falling back to the
  # company the session carried — the id is written before the redirect, so the
  # first path is the normal one and the second covers a customer created by hand
  # in the dashboard.
  def company_for(object)
    customer_id = object.respond_to?(:customer) ? object.customer : nil
    by_customer = Company.find_by(stripe_customer_id: customer_id) if customer_id.present?
    return by_customer if by_customer

    company_id = object.respond_to?(:metadata) ? object.metadata&.[]("company_id") : nil
    Company.find_by(id: company_id) if company_id.present?
  end

  def activate(company, session)
    company.update!(
      stripe_customer_id: session.customer.presence || company.stripe_customer_id,
      stripe_subscription_id: session.subscription.presence || company.stripe_subscription_id,
      billing_state: "active",
      billing_cancels_at: nil,
      **applied
    )
    Rails.logger.info("[Webhooks::Stripe] company #{company.id} is paying")
  end

  # A running subscription is adopted whichever one it is: a canceled one never
  # runs again, so a running one is the company's current subscription. Stopping
  # is narrower — see #current_subscription?.
  #
  # `past_due` stops the company. Stripe sends it together with
  # `invoice.payment_failed`, in no promised order, and the two must agree or the
  # company flips between running and stopped on delivery order.
  def follow(company, subscription)
    if subscription.running?
      company.update!(billing_state: "active", stripe_subscription_id: subscription.id,
                      billing_cancels_at: subscription.cancels_at, **period_of(subscription), **applied)
    elsif !current_subscription?(company, subscription.id)
      ignore(company, "subscription #{subscription.id} #{subscription.status}, not its current one")
    elsif subscription.unpaid?
      block(company, "payment_failed", "subscription #{subscription.status}") unless company.billing_status == "canceled"
    elsif subscription.ended?
      ended(company, subscription)
    end
  end

  def ended(company, subscription)
    return ignore(company, "end of #{subscription.id}, not its current one") unless current_subscription?(company, subscription.id)

    block(company, "canceled", "subscription ended",
          billing_cancels_at: subscription.ended_at || subscription.cancels_at || Time.current)
  end

  # An invoice that fails after the subscription has ended — the final one, for
  # the last period's minutes — is Stripe's to chase. Treating it as a failed
  # payment would offer a "pay to restore access" for a subscription that no
  # longer exists.
  def payment_failed(company, invoice)
    subscription_id = subscription_of(invoice)
    return ignore(company, "failed invoice for #{subscription_id}, not its current one") unless current_subscription?(company, subscription_id)
    return if company.billing_status == "canceled"

    block(company, "payment_failed", "invoice #{invoice.id} unpaid",
          billing_unpaid_invoice_url: invoice.try(:hosted_invoice_url))
  end

  def paid(company, invoice)
    return unless company.billing_status == "payment_failed"
    return unless current_subscription?(company, subscription_of(invoice))

    company.update!(billing_state: "active", **applied)
    Rails.logger.info("[Webhooks::Stripe] company #{company.id} paid #{invoice.id} and runs again")
  end

  # Back to blocked rather than to trialing: the free allowance was spent once and
  # is not given back by cancelling.
  def block(company, reason, detail, **attributes)
    company.update!(billing_state: "blocked", billing_block_reason: reason, **attributes, **applied)
    Rails.logger.info("[Webhooks::Stripe] company #{company.id} stopped: #{reason} (#{detail})")
  end

  # A customer who cancelled and came back has had two subscriptions, and Stripe
  # does not deliver events in order. Only the subscription the company is on now
  # may stop it — a late `deleted` for the old one would otherwise stop a company
  # that is paying again.
  def current_subscription?(company, subscription_id)
    company.stripe_subscription_id.blank? || subscription_id.blank? ||
      company.stripe_subscription_id == subscription_id
  end

  # API 2025-03-31 moved an invoice's subscription under `parent`; the version a
  # payload is shaped by belongs to the endpoint.
  def subscription_of(invoice)
    data = invoice.to_hash.deep_symbolize_keys
    data.dig(:parent, :subscription_details, :subscription) || data[:subscription]
  end

  def period_of(subscription)
    { billing_period_starts_at: subscription.period_starts_at,
      billing_period_ends_at: subscription.period_ends_at }.compact
  end

  # Stripe does not deliver in order, and a delivery that failed is retried for
  # days. A `customer.subscription.updated` from before a failed payment or a
  # cancellation, arriving after it, would start the company again without
  # anyone paying. Strictly older only: events created in the same second are
  # the halves of one change (`past_due` and `invoice.payment_failed`), and they
  # agree.
  def stale?(company)
    @event_at.present? && company.billing_event_at.present? && @event_at < company.billing_event_at
  end

  def applied
    @event_at ? { billing_event_at: @event_at } : {}
  end

  def ignore(company, what)
    Rails.logger.info("[Webhooks::Stripe] company #{company.id}: ignored #{what}")
  end

  def client
    @client ||= Billing::StripeClient.new
  end

  # Enforced before anything reads the body, so an oversized payload is refused
  # rather than buffered and parsed first.
  def enforce_payload_limit
    return if request.content_length.to_i <= MAX_PAYLOAD_BYTES

    head :payload_too_large
  end
end
