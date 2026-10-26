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

  test "a cancelled company sees its final invoice: being prepared, then issued" do
    @company.update!(billing_state: "blocked", billing_block_reason: "canceled")
    cancellation = create(:billing_cancellation, company: @company, settlement_state: "settling")

    assert_equal "settling", billing_props[:billing][:finalInvoice][:state]

    cancellation.update!(settlement_state: "settled", final_invoice_url: "https://invoice.stripe.test/in_1")

    invoice = billing_props[:billing][:finalInvoice]
    assert_equal "settled", invoice[:state]
    assert_equal "https://invoice.stripe.test/in_1", invoice[:url]
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

  # Hiding the tab from a workspace AWS bills made its billing look missing
  # rather than kept in AWS; drawing the tab but refusing the page was no
  # better. So the refusal is what goes: the page opens and
  # says where the bill comes from, and the controls that would be a second bill
  # for the same capacity are the only thing withheld.
  test "a company AWS bills keeps the tab, and the page says where its bill is" do
    @company.update!(billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    create(:marketplace_license, :active, company: @company)

    get company_settings_billing_path

    assert_response :success
    assert_inertia_props do |props|
      assert props[:marketplaceBilling], "the page says AWS bills this workspace"
      assert props[:permissions][:canViewBilling], "so the tab is offered"
      assert_not props[:permissions][:canManageBilling], "and nothing on it is ours to change"
    end
  end

  # The figure a customer checks against their AWS bill, so it has to be what
  # AWS was sent and not what the workspace was offered. The two differ on every
  # workspace that moved payers mid-month, on every hour measured but not yet
  # sent, and on the remainder of every hour -- a record carries whole minutes.
  test "the AWS panel counts the minutes AWS has a receipt for, not the minutes offered" do
    @company.update!(billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    license = create(:marketplace_license, :active, company: @company)
    hour = Time.current.utc.beginning_of_month + 3.hours

    # Sent, and AWS answered: 90.6 minutes offered, 90 on the record.
    CapacityMeterReport.create!(provider: Billing::Meter::AwsMarketplaceSaas.provider, period_start: hour,
                                quantity_seconds: 5436, state: "reported",
                                breakdown: { @company.id.to_s => 5436 },
                                receipts: { license.license_arn => "mr-1" })
    # Measured and not sent. Real minutes, on no AWS bill yet.
    CapacityMeterReport.create!(provider: Billing::Meter::AwsMarketplaceSaas.provider, period_start: hour + 1.hour,
                                quantity_seconds: 3600, state: "pending",
                                breakdown: { @company.id.to_s => 3600 }, receipts: {})
    # The offered ledger holds both, and that is what this used to read.
    CompanyCapacityUsage.record!(company_id: @company.id, period_start: hour, quantity_seconds: 5436)
    CompanyCapacityUsage.record!(company_id: @company.id, period_start: hour + 1.hour, quantity_seconds: 3600)

    get company_settings_billing_path

    assert_inertia_props do |props|
      assert_in_delta 90.0, props.dig(:marketplaceBilling, :reportedMinutes)
    end
  end

  # The other half of the same rule, and the one that was a dead end: a customer
  # who unsubscribes in AWS keeps `billing_provider`, so keying the refusal on
  # the payer rather than on a live subscription left them unable to pay by card
  # ever again -- workspace stopped, data intact, no way out but AWS.
  test "a company whose subscription ended may pay by card again" do
    @company.update!(billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    create(:marketplace_license, :ended, company: @company)

    get company_settings_billing_path

    assert_response :success
    assert_inertia_props do |props|
      assert props[:permissions][:canManageBilling], "the card is how it pays now"
      assert props.dig(:marketplaceBilling, :ended), "and the panel still says what became of the AWS one"
    end
  end

  # The window AWS still meters into. A card started here would bill the same
  # hour twice.
  test "a company still inside the final metering window may not" do
    @company.update!(billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    create(:marketplace_license, :ending, company: @company)

    post company_billing_checkout_path

    assert_redirected_to company_settings_path
    assert_match(/AWS Marketplace/, flash[:alert])
  end

  # The actions are still refused. Only the page that explains them is not.
  test "a company AWS bills cannot add a card, cancel, or pay an invoice here" do
    @company.update!(billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    create(:marketplace_license, :active, company: @company)

    post company_billing_checkout_path
    assert_redirected_to company_settings_path
    assert_match(/AWS Marketplace/, flash[:alert])

    post company_billing_cancellation_path
    assert_redirected_to company_settings_path

    post company_billing_invoice_payment_path
    assert_redirected_to company_settings_path
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
