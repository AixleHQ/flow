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

  test "a trialing company sees its trial and no usage to invoice" do
    freeze_time
    @company.update!(billing_state: "trialing", stripe_subscription_id: nil)

    billing = billing_props[:billing]

    assert_equal "trialing", billing[:status]
    assert_equal({ "days" => 14, "daysLeft" => 14, "lastDay" => (Date.current + 13).iso8601 }, billing[:trial])
    assert_nil billing[:usage]
  end

  test "the page says what bills the workspace, so it knows whose price to quote" do
    assert_equal "stripe", billing_props[:billing][:provider]

    @company.update!(billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)

    assert_equal "aws_marketplace", billing_props[:billing][:provider]
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
      assert_equal "aws_marketplace", props.dig(:subscriptions, :active, :kind), "the page says AWS bills this workspace"
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
      assert_in_delta 90.0, props.dig(:subscriptions, :active, :usage, :workerMinutes)
    end
  end

  # An hour AWS refused for having been told a different number is marked on
  # the ledger so that it is not sent again, and it is on nobody's bill.
  test "the AWS panel does not count an hour AWS disputed" do
    @company.update!(billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    license = create(:marketplace_license, :active, company: @company)
    hour = Time.current.utc.beginning_of_month + 3.hours

    CapacityMeterReport.create!(provider: Billing::Meter::AwsMarketplaceSaas.provider, period_start: hour,
                                quantity_seconds: 3600, state: "reported",
                                breakdown: { @company.id.to_s => 3600 },
                                receipts: { license.license_arn => "mr-1" })
    [ hour + 1.hour, hour + 2.hours ].each do |disputed|
      CapacityMeterReport.create!(provider: Billing::Meter::AwsMarketplaceSaas.provider, period_start: disputed,
                                  quantity_seconds: 3600, state: "reported",
                                  breakdown: { @company.id.to_s => 3600 },
                                  receipts: { license.license_arn => Billing::Meter::AwsMarketplaceSaas::DISPUTED })
    end

    get company_settings_billing_path

    assert_inertia_props do |props|
      assert_in_delta 60.0, props.dig(:subscriptions, :active, :usage, :workerMinutes), 0.001,
                      "the honoured hour alone; two disputed hours count for nothing, not for one"
    end
  end

  # The listing's own page is where a subscription is taken out, and it cannot
  # be derived from anything the catalogue API answers. The subscription
  # library is no stand-in on a button that offers to pay through AWS, so where
  # no page is configured the offer is simply not made.
  test "the page names the listing page when one is configured, and nothing otherwise" do
    get company_settings_billing_path
    assert_inertia_props { |props| assert_nil props[:listingUrl] }

    Settings.stubs(:aws_marketplace).returns(
      Hashie::Mash.new(saas: { listing_url: "https://aws.amazon.com/marketplace/pp/prodview-x" })
    )
    get company_settings_billing_path
    assert_inertia_props do |props|
      assert_equal "https://aws.amazon.com/marketplace/pp/prodview-x", props[:listingUrl]
    end
  end

  # AWS ends the agreement and deprovisions the licence seconds apart, and the
  # workspace is stopped at the first. Between the two the banner already said
  # the subscription had ended while this panel still said Active.
  test "the page lists a closing subscription among the ended ones, as the banner does" do
    @company.update!(billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE, stripe_subscription_id: nil)
    create(:marketplace_license, :ending, company: @company)

    get company_settings_billing_path

    assert_inertia_props do |props|
      assert_nil props.dig(:subscriptions, :active)
      assert_equal "cancelled", props.dig(:subscriptions, :previous, 0, :status)
    end
  end

  # The figure an administrator decides on. The final invoice replays the last
  # closed hour in case the :05 run has not delivered it; where it has, Stripe
  # holds that hour already under the same identifier, and counting it again
  # showed an hour more than the invoice would carry.
  test "the final invoice an administrator is shown leaves out an hour the card was already sent" do
    hour = Time.utc(2026, 10, 20, 10)
    CompanyCapacityChange.record!(company_id: @company.id, max_sessions: 1, occurred_at: hour - 3.hours)
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 1)
    CapacityMeterReport.create!(provider: Billing::Meter::Stripe.provider, period_start: hour - 1.hour,
                                quantity_seconds: 3600, state: "reported",
                                breakdown: { @company.id.to_s => 3600 }, receipts: {})
    create(:marketplace_license, :active, proposed_company: @company, proposal_state: "pending",
                                          proposed_by_email: "dana@#{@company.email_domain}", proposed_at: hour)

    travel_to(hour + 30.minutes) { get company_settings_billing_path }

    assert_inertia_props do |props|
      assert_in_delta 30.0, props.dig(:marketplaceProposal, :finalInvoiceMinutes), 0.001,
                      "the half-hour now running; the hour before it is already with Stripe"
    end
  end

  # The hourly meter is not the only path that sends. A cancellation sends the
  # last part-hour through the final meter, which writes no ledger row -- so a
  # figure built from ledger rows alone understated what AWS had been told by
  # exactly the minutes a cancelling customer is most likely to check.
  #
  # And the two cancellation events send the same record, which AWS answers
  # twice with the id it issued first: counted by receipt, that lands once.
  test "the AWS panel counts the final meter too, and counts a repeated receipt once" do
    @company.update!(billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    license = create(:marketplace_license, :ended, company: @company)
    hour = Time.current.utc.beginning_of_month + 3.hours

    CapacityMeterReport.create!(provider: Billing::Meter::AwsMarketplaceSaas.provider, period_start: hour,
                                quantity_seconds: 3600, state: "reported",
                                breakdown: { @company.id.to_s => 3600 },
                                receipts: { license.license_arn => "mr-hourly" })
    # The cancellation: two events, one record, one receipt answered twice.
    %w[ev-ended ev-deprovisioned].each do |id|
      MarketplaceSubscriptionEvent.create!(
        event_id: id, detail_type: "Purchase Agreement Ended", occurred_at: hour + 1.hour,
        marketplace_license: license, applied_at: Time.current,
        metered: "sent=1:already=0:minutes=9:receipt=mr-final", metered_receipts: { "mr-final" => 9 }
      )
    end

    get company_settings_billing_path

    assert_inertia_props do |props|
      assert_in_delta 69.0, props.dig(:subscriptions, :previous, 0, :usage, :workerMinutes), 0.001,
                      "60 from the hourly ledger and 9 from the final meter, the repeat counted once"
    end
  end

  # A workspace that has gone back to a card still gets an AWS bill at the end
  # of the month for what it ran there. The page used to drop the AWS panel the
  # moment the card arrived -- leaving it saying "0 worker-minutes this period"
  # beside a charge it never mentioned. Now the ended subscription stays
  # listed, with the minutes that bill is counted from.
  test "an ended AWS subscription stays listed beneath the card that took over" do
    license = create(:marketplace_license, :ended, company: @company)
    CapacityMeterReport.create!(provider: Billing::Meter::AwsMarketplaceSaas.provider,
                                period_start: Time.current.utc.beginning_of_month + 3.hours,
                                quantity_seconds: 5820, state: "reported",
                                breakdown: { @company.id.to_s => 5820 },
                                receipts: { license.license_arn => "mr-1" })
    @company.update!(billing_provider: Company::BILLING_PROVIDER_STRIPE)

    get company_settings_billing_path

    assert_inertia_props do |props|
      assert_equal "card", props.dig(:subscriptions, :active, :kind), "the card is what runs the workspace now"
      aws = props.dig(:subscriptions, :previous, 0)
      assert_equal "aws_marketplace", aws[:kind]
      assert_equal "cancelled", aws[:status]
      assert_in_delta 97.0, aws.dig(:usage, :workerMinutes)
      assert props[:permissions][:canManageBilling], "and the card is what it manages now"
    end
  end

  # Listed all the same: the subscription was there, and what it sent was nothing.
  test "an ended AWS subscription that sent nothing is listed with nothing on its bill" do
    create(:marketplace_license, :ended, company: @company)
    @company.update!(billing_provider: Company::BILLING_PROVIDER_STRIPE)

    get company_settings_billing_path

    assert_inertia_props do |props|
      aws = props.dig(:subscriptions, :previous, 0)
      assert_equal "aws_marketplace", aws[:kind]
      assert_in_delta 0.0, aws.dig(:usage, :workerMinutes)
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
      assert_equal "cancelled", props.dig(:subscriptions, :previous, 0, :status),
                   "and the AWS one is listed among those that ended"
    end
  end

  test "the page quotes the price the card is billed at" do
    price = billing_props[:billing][:price]

    assert_in_delta 500.0, price[:unitAmountCents]
    assert_equal "usd", price[:currency]
    assert_equal 60, price[:minutesPerUnit]
  end

  test "the card paying now is the active subscription, with its period and usage" do
    used!(Time.utc(2026, 10, 2, 9), 130)

    active = billing_props[:subscriptions][:active]

    assert_equal "card", active[:kind]
    assert_equal "active", active[:status]
    assert_equal Time.utc(2026, 11, 1), Time.zone.parse(active[:nextInvoiceAt])
    assert_in_delta 130.0, active.dig(:usage, :workerMinutes)
    assert_equal 1000, active.dig(:usage, :estimate, :amountCents)
    assert_empty billing_props[:subscriptions][:previous]
  end

  # What the tab lists a stopped card under: the period the card paid for, and
  # the usage its final invoice covered -- the last period's, not the tail the
  # cancellation still owed Stripe.
  test "a stopped card is listed with its active period and what its final invoice covered" do
    @company.update!(billing_state: "blocked", billing_block_reason: "canceled",
                     billing_cancels_at: Time.utc(2026, 10, 20, 9))
    create(:billing_cancellation, company: @company, cancels_at: Time.utc(2026, 10, 20, 9),
                                  started_at: Time.utc(2026, 7, 1, 9), period_started_at: Time.utc(2026, 10, 1),
                                  settlement_state: "settled", final_invoice_url: "https://invoice.stripe.test/in_1")
    used!(Time.utc(2026, 9, 30, 23), 600) # the period before: already invoiced
    used!(Time.utc(2026, 10, 2, 9), 100)
    used!(Time.utc(2026, 10, 19, 10), 30)

    subscriptions = billing_props[:subscriptions]

    assert_nil subscriptions[:active]
    card = subscriptions[:previous].first
    assert_equal "card", card[:kind]
    assert_equal "cancelled", card[:status]
    assert_equal Time.utc(2026, 7, 1, 9), Time.zone.parse(card[:periodStartsAt])
    assert_equal Time.utc(2026, 10, 20, 9), Time.zone.parse(card[:cancelledAt])
    assert_equal Time.utc(2026, 10, 1), Time.zone.parse(card.dig(:usage, :since))
    assert_in_delta 130.0, card.dig(:usage, :workerMinutes)
    assert_equal 1000, card.dig(:usage, :estimate, :amountCents)
    assert_equal "https://invoice.stripe.test/in_1", card[:invoicesUrl]
    assert_equal "settled", card.dig(:finalInvoice, :state)
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
