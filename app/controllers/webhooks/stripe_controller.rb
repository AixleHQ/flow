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
    customer.subscription.updated
    customer.subscription.deleted
    invoice.payment_failed
  ].freeze

  # A subscription Stripe considers good enough to keep serving. `past_due` is
  # deliberately included: a failed payment starts a dunning cycle that usually
  # ends in payment, and stopping a customer's work on the first retry is a worse
  # mistake than carrying them for a few days.
  RUNNING_STATUSES = %w[active trialing past_due].freeze

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

    case event.type
    when "checkout.session.completed" then activate(company, object)
    when "customer.subscription.updated" then follow_status(company, object)
    when "customer.subscription.deleted", "invoice.payment_failed" then block(company, event.type)
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
      billing_state: "active"
    )
    Rails.logger.info("[Webhooks::Stripe] company #{company.id} is paying")
  end

  def follow_status(company, subscription)
    if RUNNING_STATUSES.include?(subscription.status)
      company.update!(billing_state: "active", stripe_subscription_id: subscription.id)
    else
      block(company, "subscription #{subscription.status}")
    end
  end

  # Back to blocked rather than to trialing: the free allowance was spent once and
  # is not given back by cancelling.
  def block(company, reason)
    return if company.billing_blocked?

    company.update!(billing_state: "blocked")
    Rails.logger.info("[Webhooks::Stripe] company #{company.id} stopped (#{reason})")
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
