# frozen_string_literal: true

require "test_helper"

class Billing::Meter::AwsMarketplaceSaasTest < ActiveSupport::TestCase
  setup do
    @client = FakeMarketplaceSellerClient.new
    @adapter = Billing::Meter::AwsMarketplaceSaas.new(client: @client)
    @hour = Time.utc(2026, 10, 22, 9)
  end

  def marketplace_company(minutes:, state: "active")
    company = create(:company, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    license = create(:marketplace_license, company: company, subscription_state: state)
    [ company, license, (minutes * 60).to_i ]
  end

  def report(seconds_by_company)
    CapacityMeterReport.create!(
      provider: @adapter.provider, period_start: @hour, state: "pending",
      quantity_seconds: seconds_by_company.values.sum,
      breakdown: seconds_by_company.transform_keys(&:to_s)
    )
  end

  test "it names the provider apart from the container product" do
    assert_equal "aws_marketplace_saas", @adapter.provider
    assert_not_equal Billing::Meter::AwsMarketplace.provider, @adapter.provider
  end

  # The container product's dimension is published and cannot move, and the two
  # products do not bill for the same thing.
  test "its dimension is its own" do
    assert_not_equal Billing::Meter::AwsMarketplace::DIMENSION,
                     Billing::Meter::AwsMarketplaceSaas::DIMENSION
  end

  test "it bills each licence separately, keyed on the licence and not the product" do
    first, first_license, first_seconds = marketplace_company(minutes: 60)
    second, second_license, second_seconds = marketplace_company(minutes: 30)

    external_id = @adapter.deliver(report(first.id => first_seconds, second.id => second_seconds))

    assert_equal 2, @client.recorded.size
    by_license = @client.recorded.index_by(&:license_arn)
    assert_equal 60, by_license[first_license.license_arn].quantity
    assert_equal 30, by_license[second_license.license_arn].quantity
    assert_equal [ @hour, @hour ], @client.recorded.map(&:occurred_at)
    assert_match(/sent=2/, external_id)
  end

  # Each licence is its own bill, so there is no remainder to redistribute —
  # unlike the container product, where one call carries one quantity.
  test "each licence's minutes are floored on their own" do
    company, license, _ = marketplace_company(minutes: 0)
    seconds = (10.5 * 60).to_i

    @adapter.deliver(report(company.id => seconds))

    assert_equal 10, @client.recorded.sole.quantity
    assert_equal license.license_arn, @client.recorded.sole.license_arn
  end

  test "a company a Stripe customer owns is counted, not sent" do
    paying, _, paying_seconds = marketplace_company(minutes: 60)
    stripe = create(:company, billing_provider: Company::BILLING_PROVIDER_STRIPE)

    external_id = @adapter.deliver(report(paying.id => paying_seconds, stripe.id => 3600))

    assert_equal 1, @client.recorded.size
    assert_match(/sent=1/, external_id)
    assert_match(/unbilled=1/, external_id)
  end

  # AWS discards records for an agreement it has not confirmed, so sending them
  # would report usage nobody is charged for and hide that fact behind a success.
  test "a licence AWS has not confirmed is not metered" do
    pending, _, seconds = marketplace_company(minutes: 60, state: "pending")

    external_id = @adapter.deliver(report(pending.id => seconds))

    assert_empty @client.recorded
    assert_match(/unbilled=1/, external_id)
  end

  # The hour AWS allows after an agreement closes is exactly when the last usage
  # has to go, so `ending` is still metered.
  test "a closing agreement still has its last hour reported" do
    ending, license, seconds = marketplace_company(minutes: 60, state: "ending")

    @adapter.deliver(report(ending.id => seconds))

    assert_equal license.license_arn, @client.recorded.sole.license_arn
  end

  # An hour we already hold AWS's receipt for is not sent again at all. AWS
  # answers an honest replay `Success` with the id it issued the first time, so
  # re-sending reads afterwards as a second charge that never happened.
  test "an hour already receipted is not sent a second time" do
    company, _, seconds = marketplace_company(minutes: 60)
    row = report(company.id => seconds)

    first = @adapter.deliver(row)
    second = @adapter.deliver(row)

    assert_match(/sent=1/, first)
    assert_match(/sent=0/, second)
    assert_equal 1, @client.recorded.size, "a replay must not record a second time"
  end

  # Not a replay of ours -- those carry the same quantity and come back
  # `Success`. A duplicate is AWS saying it was told a DIFFERENT number for this
  # hour and has honoured neither this one nor, necessarily, the right one. It
  # is unbilled, and no retry can settle it.
  test "a disputed hour is reported as disputed, not as sent, and is not retried" do
    company, license, seconds = marketplace_company(minutes: 60)
    @client.refuse(license.license_arn, status: Billing::MarketplaceSellerClient::DUPLICATE)

    line = @adapter.deliver(report(company.id => seconds))

    assert_match(/sent=0/, line)
    assert_match(/disputed=1/, line)
  end

  # One refusal among several is one refusal, not a failed hour. The receipts of
  # the records AWS did honour are kept, so the retry sends only what is left.
  test "a refusal keeps the receipts of the records that were honoured" do
    billed, honoured, billed_seconds = marketplace_company(minutes: 60)
    refused_company, refused_license, refused_seconds = marketplace_company(minutes: 30)
    @client.refuse(refused_license.license_arn)
    row = report(billed.id => billed_seconds, refused_company.id => refused_seconds)

    assert_raises(Billing::MarketplaceSellerClient::Error) { @adapter.deliver(row) }

    assert_equal "mr-1", row.reload.receipts[honoured.license_arn], "it was billed; the hour is not lost"
    assert_nil row.receipts[refused_license.license_arn]

    @client.refusals.delete(refused_license.license_arn)
    @adapter.deliver(row)

    assert_equal [ refused_license.license_arn ], @client.recorded.drop(1).map(&:license_arn),
                 "the retry sends only the record that was refused"
  end

  test "a licence AWS refuses fails the hour instead of reporting it sent" do
    company, license, seconds = marketplace_company(minutes: 60)
    @client.refuse(license.license_arn)

    error = assert_raises(Billing::MarketplaceSellerClient::Error) do
      @adapter.deliver(report(company.id => seconds))
    end
    assert_match(/InvalidLicense/, error.message)
    assert_match(/#{Regexp.escape(license.license_arn)}/, error.message)
  end

  test "an hour with nothing to report asks AWS for nothing" do
    stripe = create(:company, billing_provider: Company::BILLING_PROVIDER_STRIPE)

    external_id = @adapter.deliver(report(stripe.id => 3600))

    assert_empty @client.recorded
    assert_empty @client.metered
    assert_match(/sent=0/, external_id)
  end

  # The ledger replays a failed hour whole and AWS refuses what it already holds,
  # which is what makes that safe.
  test "a company whose minutes floor to nothing is left out of the call" do
    company, _, _ = marketplace_company(minutes: 0)

    @adapter.deliver(report(company.id => 30))

    assert_empty @client.recorded
  end
  # `external_id` is what we believe happened; this is what AWS says. Without
  # it the next independent check on a billed hour is the customer's invoice.
  test "AWS's own receipt for each record is kept" do
    company, license, seconds = marketplace_company(minutes: 60)
    row = report(company.id => seconds)

    @adapter.deliver(row)

    assert_equal({ license.license_arn => "mr-1" }, row.reload.receipts)
  end

  # Marked as the duplicate it is, so it does not read like a record that went
  # missing -- an hour AWS refused looks the same as one we never sent.
  test "a disputed hour is marked rather than left blank" do
    company, license, seconds = marketplace_company(minutes: 60)
    @client.refuse(license.license_arn, status: Billing::MarketplaceSellerClient::DUPLICATE)

    @adapter.deliver(report(company.id => seconds))

    assert_equal({ license.license_arn => "duplicate" }, CapacityMeterReport.sole.receipts)
  end
end
