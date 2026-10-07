# frozen_string_literal: true

# Starting card entry. Everything after this happens on Stripe's own page and
# comes back as a webhook — this controller only decides who may begin and makes
# the customer the session hangs off.
class Web::Company::BillingCheckoutsController < Web::Company::ApplicationController
  include HostedBillingOnly

  def create
    return refuse("Payment is not set up on this installation") unless client.configured?

    live = live_subscription
    return refuse(already_subscribed(live)) if live

    session = client.create_checkout_session(
      company: current_company,
      customer_id: customer_id!,
      success_url: company_settings_billing_url(billing: "done"),
      cancel_url: company_settings_billing_url(billing: "cancelled")
    )

    # 409 + X-Inertia-Location: an Inertia visit is an XHR and cannot follow a
    # cross-origin redirect, so the client is told to leave the application.
    inertia_location(session.url)
  rescue Billing::StripeClient::Error => e
    Rails.logger.error("[BillingCheckouts] company #{current_company.id}: #{e.message}")
    refuse("We could not reach our payment provider. Try again in a moment.")
  end

  private

  # A second subscription on the same customer bills the same metered minutes a
  # second time: the meter sums by customer, and every subscription carrying
  # the price invoices that sum. Asked of Stripe rather than of our columns,
  # which lag it by a webhook.
  def live_subscription
    id = current_company.stripe_subscription_id
    return nil if id.blank?

    subscription = Billing::SubscriptionState.from(client.retrieve_subscription(subscription_id: id))
    subscription.ended? ? nil : subscription
  rescue Billing::StripeClient::NotFound
    nil
  end

  def already_subscribed(subscription)
    if subscription.unpaid?
      "Your last payment did not go through. Pay the open invoice to restore access."
    else
      "This workspace already has a card on file."
    end
  end

  # Created on the first attempt and kept: a second customer for the same company
  # would split its usage across two bills.
  def customer_id!
    return current_company.stripe_customer_id if current_company.stripe_customer_id.present?

    customer = client.create_customer(company: current_company, email: current_user.email)
    current_company.update!(stripe_customer_id: customer.id)
    customer.id
  end

  def client
    @client ||= Billing::StripeClient.new
  end

  # A flash rather than a form error: the button lives on the banner as well as
  # the billing tab, and the layout shows a flash on any page.
  def refuse(message)
    redirect_back fallback_location: company_settings_billing_path, alert: message
  end
end
