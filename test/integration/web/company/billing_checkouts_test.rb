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

  test "the session comes back to the settings screen either way" do
    post company_billing_checkout_path

    opened = @client.checkout_sessions.sole
    assert_match(/billing=done/, opened[:success_url])
    assert_match(/billing=cancelled/, opened[:cancel_url])
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
    follow_redirect!
    assert_inertia_props { |props| assert_match(/not set up/, props[:errors][:base]) }
  end

  # A provider that is down must read as "try again", not as a stack trace, and
  # must not leave a customer id pointing at something that was never made.
  test "a provider failure is reported rather than raised" do
    @client.failure = "APIConnectionError: could not reach Stripe"

    post company_billing_checkout_path

    assert_nil @company.reload.stripe_customer_id
    follow_redirect!
    assert_inertia_props { |props| assert_match(/could not reach/i, props[:errors][:base]) }
  end
end
