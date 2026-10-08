# frozen_string_literal: true

require "test_helper"

# Starting card entry. Everything after this happens on Stripe's own page, so all
# this has to get right is who may begin, and that a company gets one customer
# rather than one per attempt.
class Web::Company::BillingCheckoutsTest < ActionDispatch::IntegrationTest
  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    @client = FakeStripeClient.new
    Billing::StripeClient.stubs(:new).returns(@client)
    @company = create(:company, :trialing)
    @admin = create(:user, :onboarding_completed, company: @company, membership_role: "admin",
                    password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@admin)
  end

  test "an administrator is sent to Stripe's page" do
    post company_billing_checkout_path

    # 409 + X-Inertia-Location: an Inertia visit is an XHR and cannot follow a
    # cross-origin redirect, so the client is told to leave the application.
    assert_equal @client.checkout_url, response.headers["X-Inertia-Location"]
  end

  test "the company gets a customer, and keeps it" do
    post company_billing_checkout_path
    customer_id = @company.reload.stripe_customer_id
    assert_equal "cus_fake_#{@company.id}", customer_id

    post company_billing_checkout_path

    assert_equal customer_id, @company.reload.stripe_customer_id
    assert_equal 1, @client.customers.size, "a second customer would split the company's usage across two bills"
  end

  test "the session comes back to the billing tab either way" do
    post company_billing_checkout_path

    opened = @client.checkout_sessions.sole
    assert_match(%r{/company/settings/billing\?billing=done}, opened[:success_url])
    assert_match(%r{/company/settings/billing\?billing=cancelled}, opened[:cancel_url])
  end

  # The meter sums by customer and every subscription carrying the price
  # invoices that sum, so a second subscription bills the same minutes twice.
  test "a company with a running subscription is not sent to open a second one" do
    @company.update!(billing_state: "active", stripe_customer_id: "cus_1", stripe_subscription_id: "sub_1")
    @client.add_subscription(id: "sub_1", status: "active")

    post company_billing_checkout_path

    assert_empty @client.checkout_sessions
    assert_match(/already has a card/, flash[:alert])
  end

  test "a company stopped for a failed payment is pointed at its invoice instead" do
    @company.update!(billing_state: "blocked", billing_block_reason: "payment_failed",
                     stripe_customer_id: "cus_1", stripe_subscription_id: "sub_1")
    @client.add_subscription(id: "sub_1", status: "past_due")

    post company_billing_checkout_path

    assert_empty @client.checkout_sessions
    assert_match(/Pay the open invoice/, flash[:alert])
  end

  test "a company whose subscription ended starts a new one" do
    @company.update!(billing_state: "blocked", billing_block_reason: "canceled",
                     stripe_customer_id: "cus_1", stripe_subscription_id: "sub_1")
    @client.add_subscription(id: "sub_1", status: "canceled")

    post company_billing_checkout_path

    assert_equal "cus_1", @client.checkout_sessions.sole[:session].customer
  end

  # An id Stripe no longer holds (deleted in the dashboard, cleared test data)
  # must not lock the company out of paying.
  test "a subscription id Stripe does not know does not stand in the way" do
    @company.update!(billing_state: "blocked", stripe_customer_id: "cus_1", stripe_subscription_id: "sub_gone")

    post company_billing_checkout_path

    assert_equal 1, @client.checkout_sessions.size
  end

  test "a member cannot start it" do
    member = create(:user, :onboarding_completed, company: @company, membership_role: "employee",
                    password: AuthHelper::TEST_PASSWORD)
    sign_in_as(member)

    post company_billing_checkout_path

    assert_empty @client.checkout_sessions
  end

  # An installation with no Stripe credentials must not offer a button that leads
  # nowhere, and must refuse if one is pressed anyway.
  test "an installation without a payment provider refuses" do
    @client.configured = false

    post company_billing_checkout_path

    assert_empty @client.checkout_sessions
    assert_match(/not set up/, flash[:alert])
  end

  # A provider that is down must read as "try again", not as a stack trace, and
  # must not leave a customer id pointing at something that was never made.
  test "a provider failure is reported rather than raised" do
    @client.failure = "APIConnectionError: could not reach Stripe"

    post company_billing_checkout_path

    assert_nil @company.reload.stripe_customer_id
    assert_match(/could not reach/i, flash[:alert])
  end

  # A card on a company we carry would start billing what nobody owes.
  test "a company we carry is not sent to Stripe" do
    @company.update!(managed_by_aixle: true)

    post company_billing_checkout_path

    assert_redirected_to company_settings_path
    assert_match(/managed by Aixle/, flash[:alert])
    assert_empty @client.checkout_sessions
    assert_empty @client.customers
  end

  # A self-hosted operator pays nobody: even with Stripe keys present, no
  # checkout is opened outside the hosted product.
  test "outside the hosted product no checkout starts" do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SELF_HOSTED))

    post company_billing_checkout_path

    assert_redirected_to company_settings_path
    assert_match(/not available/, flash[:alert])
    assert_empty @client.checkout_sessions
    assert_empty @client.customers
  end
end
