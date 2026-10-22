# frozen_string_literal: true

require "test_helper"

# One installation, two payers, one hour.
#
# The hour is measured once — capacity offered is not a per-provider fact — and
# each provider claims its own ledger row for it, which is what
# capacity_meter_reports was already keyed for.
class Billing::CapacityMeterTwoProvidersTest < ActiveSupport::TestCase
  setup do
    @now = Time.utc(2026, 10, 22, 11, 5)
    @hour = Time.utc(2026, 10, 22, 10)

    @seller = FakeMarketplaceSellerClient.new
    @stripe = FakeStripeMeter.new
    @marketplace = Billing::Meter::AwsMarketplaceSaas.new(client: @seller)

    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
  end

  # A real adapter over the real interface rather than a stub of the meter: the
  # Stripe one needs a Stripe key this suite has no business holding.
  class FakeStripeMeter < Billing::Meter::Base
    attr_reader :delivered

    def self.provider = Billing::Meter::Stripe.provider

    def initialize
      super()
      @delivered = []
    end

    def deliver(report)
      @delivered << report.period_start
      "stripe:#{report.period_start.to_i}"
    end
  end

  def company_with_capacity(workers:, **attributes)
    company = create(:company, **attributes)
    CompanyCapacityChange.record!(company_id: company.id, max_sessions: workers, occurred_at: @hour - 2.hours)
    SessionConcurrencyLimit.set!(scope: company, max_sessions: workers)
    company
  end

  def run_meter
    Billing::CapacityMeter.new(adapters: [ @stripe, @marketplace ], now: @now).call
  end

  def report_for(provider) = CapacityMeterReport.find_by(provider: provider, period_start: @hour)

  test "each provider gets its own row for the same hour, from one measurement" do
    company_with_capacity(workers: 2, billing_provider: Company::BILLING_PROVIDER_STRIPE,
                                      stripe_customer_id: "cus_x")
    aws = company_with_capacity(workers: 3, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    create(:marketplace_license, :active, company: aws)

    result = run_meter

    stripe_row = report_for(Billing::Meter::Stripe.provider)
    aws_row = report_for(Billing::Meter::AwsMarketplaceSaas.provider)

    assert_not_nil stripe_row
    assert_not_nil aws_row
    assert_equal "reported", stripe_row.state
    assert_equal "reported", aws_row.state
    # One measurement: both rows describe the same hour and the same capacity.
    assert_equal stripe_row.quantity_seconds, aws_row.quantity_seconds
    assert_equal BigDecimal("300"), stripe_row.quantity_minutes, "five workers for an hour"
    assert_equal 2, result[:sent]
    assert_equal 0, result[:failed]
  end

  test "each provider reports only the companies it bills" do
    stripe_company = company_with_capacity(workers: 2, billing_provider: Company::BILLING_PROVIDER_STRIPE,
                                                       stripe_customer_id: "cus_x")
    aws = company_with_capacity(workers: 3, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    license = create(:marketplace_license, :active, company: aws)

    run_meter

    assert_equal 1, @seller.recorded.size
    assert_equal license.license_arn, @seller.recorded.sole.license_arn
    assert_equal 180, @seller.recorded.sole.quantity, "three workers for an hour"

    # That the AWS company is not also counted as Stripe's is Meter::Stripe's own
    # contract, and is tested there.
    assert_equal 2, CompanyCapacityUsage.where(period_start: @hour).count
    assert_not_nil stripe_company
  end

  # One provider being down is not the other's problem, and the ledger is what
  # replays the hour that failed.
  test "a provider that fails leaves the other's hour reported" do
    aws = company_with_capacity(workers: 3, billing_provider: Company::BILLING_PROVIDER_AWS_MARKETPLACE)
    create(:marketplace_license, :active, company: aws)
    @seller.failure = Billing::MarketplaceSellerClient::CredentialsError

    result = run_meter

    assert_equal "reported", report_for(Billing::Meter::Stripe.provider).state
    assert_equal "failed", report_for(Billing::Meter::AwsMarketplaceSaas.provider).state
    assert_equal 1, result[:sent]
    assert_equal 1, result[:failed]
  end

  test "usage is recorded once per company however many providers run" do
    company = company_with_capacity(workers: 2, billing_provider: Company::BILLING_PROVIDER_STRIPE,
                                                stripe_customer_id: "cus_x")

    run_meter

    assert_equal 1, CompanyCapacityUsage.where(company_id: company.id, period_start: @hour).count
  end

  test "an installation that does not sell the listing runs Stripe alone" do
    assert_equal [ Billing::Meter::Stripe ], Billing::CapacityMeter.adapters_for(Deployment::SAAS).map(&:class)
  end

  test "an installation that sells the listing runs both" do
    Settings.stubs(:aws_marketplace).returns(
      Hashie::Mash.new(saas: { product_code: "p", seller_role_arn: "arn:aws:iam::1:role/r" })
    )

    assert_equal [ Billing::Meter::Stripe, Billing::Meter::AwsMarketplaceSaas ],
                 Billing::CapacityMeter.adapters_for(Deployment::SAAS).map(&:class)
  end
end
