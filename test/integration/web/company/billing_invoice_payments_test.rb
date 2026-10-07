# frozen_string_literal: true

require "test_helper"

# Paying the invoice that stopped the workspace, on Stripe's own page.
class Web::Company::BillingInvoicePaymentsTest < ActionDispatch::IntegrationTest
  INVOICE_URL = "https://invoice.stripe.test/i/in_1"

  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    @client = FakeStripeClient.new
    Billing::StripeClient.stubs(:new).returns(@client)
    @company = create(:company, :subscribed, billing_state: "blocked", billing_block_reason: "payment_failed",
                                             billing_unpaid_invoice_url: INVOICE_URL)
    @client.add_subscription(id: @company.stripe_subscription_id, status: "past_due")
    @admin = create(:user, :onboarding_completed, company: @company, membership_role: "admin",
                    password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@admin)
  end

  test "an admin is sent to the open invoice" do
    post company_billing_invoice_payment_path, headers: { "X-Inertia" => "true" }

    assert_equal INVOICE_URL, response.headers["X-Inertia-Location"]
  end

  # Otherwise the card that pays this invoice is not the one charged next month,
  # and the workspace stops again.
  test "the card used to pay becomes the subscription's card" do
    post company_billing_invoice_payment_path

    assert_equal({ save_default_payment_method: "on_subscription" },
                 @client.subscription_updates.sole[:payment_settings])
  end

  test "a workspace that is not stopped for a payment has no invoice to pay" do
    @company.update!(billing_state: "active")

    post company_billing_invoice_payment_path

    assert_match(/no unpaid invoice/, flash[:alert])
    assert_empty @client.subscription_updates
  end

  test "when Stripe cannot be reached the admin is told" do
    @client.failure = "APIConnectionError: could not reach Stripe"

    post company_billing_invoice_payment_path

    assert_match(/could not reach/, flash[:alert])
  end

  test "outside the hosted product no invoice is opened" do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SELF_HOSTED))

    post company_billing_invoice_payment_path, headers: { "X-Inertia" => "true" }

    assert_nil response.headers["X-Inertia-Location"]
    assert_empty @client.subscription_updates
  end
end
