# frozen_string_literal: true

# Starting card entry. Everything after this happens on Stripe's own page and
# comes back as a webhook — this controller only decides who may begin and makes
# the customer the session hangs off.
class Web::Company::BillingCheckoutsController < Web::Company::ApplicationController
  def create
    return refuse("Payment is not set up on this installation") unless client.configured?

    session = client.create_checkout_session(
      company: current_company,
      customer_id: customer_id!,
      success_url: company_settings_url(billing: "done"),
      cancel_url: company_settings_url(billing: "cancelled")
    )

    # 409 + X-Inertia-Location: an Inertia visit is an XHR and cannot follow a
    # cross-origin redirect, so the client is told to leave the application.
    inertia_location(session.url)
  rescue Billing::StripeClient::Error => e
    Rails.logger.error("[BillingCheckouts] company #{current_company.id}: #{e.message}")
    refuse("We could not reach our payment provider. Try again in a moment.")
  end

  private

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

  def refuse(message)
    redirect_to company_settings_path, inertia: { errors: { base: message } }
  end
end
