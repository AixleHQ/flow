# frozen_string_literal: true

require "test_helper"

# The Billing tab: what it tells an admin about the subscription, and what this
# period has come to so far.
class Web::Company::BillingTest < ActionDispatch::IntegrationTest
  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    @client = FakeStripeClient.new
    Billing::StripeClient.stubs(:new).returns(@client)
    @company = create(:company, :subscribed, billing_period_starts_at: Time.utc(2026, 10, 1),
                                             billing_period_ends_at: Time.utc(2026, 11, 1))
    @admin = create(:user, :onboarding_completed, company: @company, membership_role: "admin",
                    password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@admin)
  end

  test "a paying company sees its period and what it has used in it" do
    used!(Time.utc(2026, 9, 30, 23), 600) # the period before: not this invoice
    used!(Time.utc(2026, 10, 2, 9), 100)
    used!(Time.utc(2026, 10, 2, 10), 30)

    billing = billing_props[:billing]

    assert_equal "active", billing[:status]
    assert_equal Time.utc(2026, 11, 1), Time.zone.parse(billing[:periodEndsAt])
    assert_in_delta 130.0, billing[:usage][:workerMinutes]
    assert_equal Time.utc(2026, 10, 2, 11), Time.zone.parse(billing[:usage][:measuredUntil])
  end

  # The price sells minutes sixty at a time, rounded down, so 130 minutes are two
  # packs — the estimate must not promise less than the invoice will say.
  test "the estimate prices the minutes the way the subscription's price does" do
    used!(Time.utc(2026, 10, 2, 9), 130)

    estimate = billing_props[:billing][:usage][:estimate]

    assert_equal 1000, estimate[:amountCents]
    assert_equal "usd", estimate[:currency]
    assert_equal 60, estimate[:minutesPerUnit]
  end

  test "without the price the minutes are still shown" do
    @client.failure = "APIConnectionError: could not reach Stripe"
    used!(Time.utc(2026, 10, 2, 9), 30)

    usage = billing_props[:billing][:usage]

    assert_in_delta 30.0, usage[:workerMinutes]
    assert_nil usage[:estimate]
  end

  test "a scheduled cancellation shows its date" do
    @company.update!(billing_cancels_at: Time.utc(2026, 11, 1))

    billing = billing_props[:billing]

    assert_equal "cancelling", billing[:status]
    assert_equal Time.utc(2026, 11, 1), Time.zone.parse(billing[:cancelsAt])
  end

  test "a trialing company sees its allowance and no usage to invoice" do
    @company.update!(billing_state: "trialing", stripe_subscription_id: nil)
    Settings.stubs(:trial).returns(Hashie::Mash.new(queue_hours: 100))

    billing = billing_props[:billing]

    assert_equal "trialing", billing[:status]
    assert_equal 100, billing[:allowance][:hours]
    assert_nil billing[:usage]
  end

  test "the page says whether there is a subscription to cancel" do
    assert billing_props[:billing][:hasSubscription]

    @company.update!(stripe_subscription_id: nil)

    assert_equal false, billing_props[:billing][:hasSubscription] # rubocop:disable Minitest/RefuteFalse
  end

  test "Checkout's way back is reported, and nothing else from the query string" do
    get company_settings_billing_path(billing: "done")
    assert_inertia_props { |props| props[:checkoutResult] == "done" }

    get company_settings_billing_path(billing: "<script>")
    assert_inertia_props { |props| props[:checkoutResult].nil? }
  end

  test "outside the hosted product there is no billing tab" do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SELF_HOSTED))

    get company_settings_billing_path

    assert_redirected_to company_settings_path
    assert_match(/not available/, flash[:alert])
  end

  test "a company we carry has no billing tab" do
    @company.update!(managed_by_aixle: true)

    get company_settings_billing_path

    assert_redirected_to company_settings_path
    assert_match(/managed by Aixle/, flash[:alert])

    get company_settings_path
    assert_inertia_props { |props| props[:permissions][:canManageBilling] == false }
  end

  private

  def billing_props
    get company_settings_billing_path
    assert_inertia_page "Company/Settings/BillingPage"
    captured = nil
    assert_inertia_props do |props|
      captured = props
      true
    end
    captured
  end

  def used!(at, minutes)
    CompanyCapacityUsage.record!(company_id: @company.id, period_start: at, quantity_seconds: minutes * 60)
  end
end
