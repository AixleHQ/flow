# frozen_string_literal: true

# Paying the invoice whose failure stopped the workspace, on Stripe's hosted
# invoice page. Paying it there is what brings the workspace back:
# `invoice.paid` arrives as a webhook.
#
# Through here rather than a plain link, so the card used to pay becomes the
# one the subscription charges next (Billing::StripeClient#adopt_subscription).
# A customer who paid with a new card and was charged the old one next month
# would be back here in four weeks.
class Web::Company::BillingInvoicePaymentsController < Web::Company::ApplicationController
  def create
    url = current_company.billing_unpaid_invoice_url
    return refuse("There is no unpaid invoice to pay.") unless current_company.billing_status == "payment_failed" && url

    client.adopt_subscription(subscription_id: current_company.stripe_subscription_id)
    # An Inertia visit cannot follow a cross-origin redirect; see BillingCheckoutsController.
    inertia_location(url)
  rescue Billing::StripeClient::Error => e
    Rails.logger.error("[BillingInvoicePayments] company #{current_company.id}: #{e.message}")
    refuse("We could not reach our payment provider. Try again in a moment.")
  end

  private

  def client
    @client ||= Billing::StripeClient.new
  end

  def refuse(message)
    redirect_back fallback_location: company_settings_billing_path, alert: message
  end
end
