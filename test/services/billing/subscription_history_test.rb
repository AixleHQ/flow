# frozen_string_literal: true

require "test_helper"

# The list the Billing tab draws: the subscription paying now and the ones
# that ended, built from the cancellation records and the AWS licences, since
# no table of subscriptions exists.
class Billing::SubscriptionHistoryTest < ActiveSupport::TestCase
  setup do
    @client = FakeStripeClient.new
    @price = Billing::CardPrice.new(client: @client)
    @now = Time.utc(2026, 11, 2, 12)
    @company = create(:company, :subscribed, billing_provider: Company::BILLING_PROVIDER_STRIPE,
                                             billing_period_starts_at: Time.utc(2026, 10, 28, 9),
                                             billing_period_ends_at: Time.utc(2026, 11, 28, 9))
  end

  def history = Billing::SubscriptionHistory.new(@company.reload, price: @price, now: @now).to_h

  def used!(at, minutes)
    CompanyCapacityUsage.record!(company_id: @company.id, period_start: at, quantity_seconds: minutes * 60)
  end

  def reported!(license, at, seconds, receipt)
    CapacityMeterReport.create!(provider: Billing::Meter::AwsMarketplaceSaas.provider, period_start: at,
                                quantity_seconds: seconds, state: "reported",
                                breakdown: { @company.id.to_s => seconds },
                                receipts: { license.license_arn => receipt })
  end

  test "the card paying now is active, with the period under way and what it has used in it" do
    used!(Time.utc(2026, 10, 27, 23), 600) # the period before
    used!(Time.utc(2026, 10, 29, 14), 130)

    active = history[:active]

    assert_equal "card", active[:kind]
    assert_equal "active", active[:status]
    assert_equal Time.utc(2026, 10, 28, 9), active[:period_starts_at]
    assert_equal Time.utc(2026, 11, 28, 9), active[:next_invoice_at]
    assert_in_delta 130.0, active.dig(:usage, :worker_minutes)
    assert_equal Time.utc(2026, 10, 29, 15), active.dig(:usage, :measured_until)
    assert_equal 1000, active.dig(:usage, :estimate, :amount_cents), "two whole packs of sixty"
  end

  test "a cancellation scheduled for the end of the period is still the running card's" do
    @company.update!(billing_cancels_at: Time.utc(2026, 11, 28, 9))
    @company.billing_cancellations.create!(reason: "unused", cancels_at: Time.utc(2026, 11, 28, 9))

    assert_equal "cancelling", history[:active][:status]
    assert_empty history[:previous]
  end

  test "a stopped card is listed with its active period and the usage its final invoice covered" do
    @company.update!(billing_state: "blocked", billing_block_reason: "canceled")
    create(:billing_cancellation, company: @company, cancels_at: Time.utc(2026, 10, 20, 9, 30),
                                  started_at: Time.utc(2026, 7, 1, 9), period_started_at: Time.utc(2026, 10, 1),
                                  settlement_state: "settled", final_invoice_url: "https://invoice.stripe.test/in_1")
    used!(Time.utc(2026, 9, 30, 23), 600)
    used!(Time.utc(2026, 10, 2, 9), 100)
    used!(Time.utc(2026, 10, 20, 9), 30) # the part-hour the cancellation measured

    assert_nil history[:active]
    card = history[:previous].sole
    assert_equal "card", card[:kind]
    assert_equal "cancelled", card[:status]
    assert_equal Time.utc(2026, 7, 1, 9), card[:period_starts_at]
    assert_equal Time.utc(2026, 10, 20, 9, 30), card[:period_ends_at]
    assert_equal Time.utc(2026, 10, 20, 9, 30), card[:cancelled_at]
    assert_equal Time.utc(2026, 10, 1), card.dig(:usage, :since)
    assert_in_delta 130.0, card.dig(:usage, :worker_minutes)
    assert_equal 1000, card.dig(:usage, :estimate, :amount_cents)
    assert_equal "https://invoice.stripe.test/in_1", card[:invoices_url]
    assert_equal({ state: "settled", url: "https://invoice.stripe.test/in_1" }, card[:final_invoice])
  end

  # Rows from before the period was recorded know only the hours they still
  # owed Stripe, which is not what their invoice covered.
  test "a cancellation recorded before the period was kept lists no usage" do
    @company.update!(billing_state: "blocked", billing_block_reason: "canceled")
    create(:billing_cancellation, company: @company, cancels_at: Time.utc(2026, 10, 20, 9, 30),
                                  settlement_state: "settled",
                                  final_usage: { Time.utc(2026, 10, 20, 8).iso8601 => 3600,
                                                 Time.utc(2026, 10, 20, 9).iso8601 => 1800 })
    used!(Time.utc(2026, 10, 2, 9), 100)
    used!(Time.utc(2026, 10, 20, 8), 60)
    used!(Time.utc(2026, 10, 20, 9), 30)

    card = history[:previous].sole

    assert_nil card[:period_starts_at]
    assert_nil card[:usage]
    assert_equal "cancelled", card[:status]
  end

  test "a live AWS subscription is active for the calendar month, billed by the minute" do
    @company.update!(billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE, stripe_subscription_id: nil)
    license = create(:marketplace_license, :active, company: @company, subscribed_at: Time.utc(2026, 9, 15, 10),
                                                    price_per_minute: BigDecimal("0.08333333"), price_currency: "USD")
    reported!(license, Time.utc(2026, 10, 31, 23), 3600, "mr-october") # last month's bill
    reported!(license, Time.utc(2026, 11, 1, 8), 2700, "mr-1")
    reported!(license, Time.utc(2026, 11, 1, 9), 2700, "mr-2")
    reported!(license, Time.utc(2026, 11, 1, 10), 3600, Billing::Meter::AwsMarketplaceSaas::DISPUTED)

    active = history[:active]

    assert_equal "aws_marketplace", active[:kind]
    assert_equal Time.utc(2026, 11, 1), active[:period_starts_at]
    assert_equal Time.utc(2026, 12, 1), active[:next_invoice_at]
    assert_equal "444455556666", active[:aws_account_id]
    assert_in_delta 90.0, active.dig(:usage, :worker_minutes), 0.001, "two honoured hours; the disputed one is on nobody's bill"
    assert_equal 750, active.dig(:usage, :estimate, :amount_cents), "ninety minutes at the agreement's rate, no packs"
    assert_equal "usd", active.dig(:usage, :estimate, :currency)
    assert_equal Billing::SubscriptionHistory::AWS_BILLING_URL, active[:invoices_url]
    assert_empty history[:previous]
  end

  # The agreement's rate, not the listing's: a private offer is priced on its own
  # terms, and a licence that never learned them shows minutes and no sum.
  test "AWS usage is priced at what the agreement was accepted at, or not at all" do
    @company.update!(billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE, stripe_subscription_id: nil)
    license = create(:marketplace_license, :active, company: @company, price_per_minute: BigDecimal("0.05"),
                                                    price_currency: "EUR")
    reported!(license, Time.utc(2026, 11, 1, 8), 3600, "mr-1")

    estimate = history[:active].dig(:usage, :estimate)
    assert_equal 300, estimate[:amount_cents]
    assert_equal "eur", estimate[:currency]

    license.update!(price_per_minute: nil, price_currency: nil)

    assert_nil history[:active].dig(:usage, :estimate)
    assert_in_delta 60.0, history[:active].dig(:usage, :worker_minutes)
  end

  # The final usage is the month the subscription ended in -- the bill it lands
  # on -- from both paths that send: the hourly meter and the final meter a
  # cancellation runs, which writes no ledger row.
  test "an ended AWS subscription is listed with the month its last bill covers" do
    @company.update!(billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE, stripe_subscription_id: nil,
                     billing_state: "blocked", billing_block_reason: "canceled")
    license = create(:marketplace_license, :ended, company: @company, subscribed_at: Time.utc(2026, 6, 12, 8),
                                                   ended_at: Time.utc(2026, 10, 27, 16, 20))
    reported!(license, Time.utc(2026, 9, 30, 10), 3600, "mr-september")
    reported!(license, Time.utc(2026, 10, 26, 10), 3600, "mr-1")
    %w[ev-ended ev-deprovisioned].each do |id|
      MarketplaceSubscriptionEvent.create!(
        event_id: id, detail_type: Billing::MarketplaceEvents::ENDED, occurred_at: Time.utc(2026, 10, 27, 16, 20),
        marketplace_license: license, applied_at: @now, metered_receipts: { "mr-final" => 24 }
      )
    end

    assert_nil history[:active]
    aws = history[:previous].sole
    assert_equal "aws_marketplace", aws[:kind]
    assert_equal "cancelled", aws[:status]
    assert_equal Time.utc(2026, 6, 12, 8), aws[:period_starts_at]
    assert_equal Time.utc(2026, 10, 27, 16, 20), aws[:cancelled_at]
    assert_equal Time.utc(2026, 10, 1), aws.dig(:usage, :since)
    assert_equal Time.utc(2026, 10, 27, 16, 20), aws.dig(:usage, :until)
    assert_in_delta 84.0, aws.dig(:usage, :worker_minutes), 0.001, "October's hour and the final meter, its repeat counted once"
  end

  # AWS ends the agreement and deprovisions the licence seconds apart; the
  # workspace is stopped at the first, so the closing subscription is already
  # one that ended, dated by the event that closed it.
  test "a closing AWS subscription is listed among the ended, dated by the event that closed it" do
    @company.update!(billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE, stripe_subscription_id: nil)
    license = create(:marketplace_license, :ending, company: @company)
    MarketplaceSubscriptionEvent.create!(event_id: "ev-ended", detail_type: Billing::MarketplaceEvents::ENDED,
                                         occurred_at: Time.utc(2026, 11, 2, 11, 40), marketplace_license: license)

    assert_nil history[:active]
    assert_equal Time.utc(2026, 11, 2, 11, 40), history[:previous].sole[:cancelled_at]
  end

  test "the ended subscriptions are listed latest first, whatever paid for them" do
    @company.update!(billing_state: "blocked", billing_block_reason: "canceled")
    create(:billing_cancellation, company: @company, cancels_at: Time.utc(2026, 6, 12, 8), settlement_state: "settled")
    create(:marketplace_license, :ended, company: @company, subscribed_at: Time.utc(2026, 6, 12, 8),
                                         ended_at: Time.utc(2026, 10, 27, 16))
    create(:billing_cancellation, company: @company, cancels_at: Time.utc(2026, 3, 1, 8), settlement_state: "settled")

    assert_equal [ [ "aws_marketplace", Time.utc(2026, 10, 27, 16) ], [ "card", Time.utc(2026, 6, 12, 8) ],
                   [ "card", Time.utc(2026, 3, 1, 8) ] ],
                 history[:previous].map { |entry| [ entry[:kind], entry[:cancelled_at] ] }
  end

  # The ledger keeps seconds; the page shows minutes as a count, not a reading.
  test "a card's minutes are listed whole" do
    CompanyCapacityUsage.record!(company_id: @company.id, period_start: Time.utc(2026, 10, 29, 14), quantity_seconds: 3168)

    assert_in_delta 53.0, history[:active].dig(:usage, :worker_minutes)
  end

  test "without the price the minutes are still listed" do
    @client.failure = "APIConnectionError: could not reach Stripe"
    used!(Time.utc(2026, 10, 29, 14), 130)

    usage = history[:active][:usage]

    assert_in_delta 130.0, usage[:worker_minutes]
    assert_nil usage[:estimate]
  end
end
