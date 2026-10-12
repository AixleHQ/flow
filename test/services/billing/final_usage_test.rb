# frozen_string_literal: true

require "test_helper"

class Billing::FinalUsageTest < ActiveSupport::TestCase
  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    @company = create(:company, :subscribed)
    CompanyCapacityChange.record!(company_id: @company.id, max_sessions: 2, occurred_at: 1.day.ago)
    @now = Time.utc(2026, 10, 12, 14, 20)
  end

  def final_usage = Billing::FinalUsage.new(@company, until_time: @now)

  def report(hour, state:, seconds:)
    CapacityMeterReport.create!(provider: "stripe", period_start: hour, quantity_seconds: seconds,
                                breakdown: { @company.id.to_s => seconds }, state: state)
  end

  test "the hour under way counts up to the cancellation, and an hour the meter has not reached in full" do
    travel_to @now do
      assert_equal({ Time.utc(2026, 10, 12, 13) => 2 * 3600, Time.utc(2026, 10, 12, 14) => 2 * 20 * 60 },
                   final_usage.billed)
    end
  end

  # Stripe takes about a minute to count an event, so the hour just closed may
  # not be on the invoice yet even when it was sent; older hours that were sent
  # are.
  test "the hours the meter sent are left to it, except the one that has only just closed" do
    report(Time.utc(2026, 10, 12, 12), state: "reported", seconds: 7200)
    report(Time.utc(2026, 10, 12, 13), state: "reported", seconds: 3600)

    travel_to @now do
      billed = final_usage.billed

      assert_not billed.key?(Time.utc(2026, 10, 12, 12))
      assert_equal 3600, billed[Time.utc(2026, 10, 12, 13)], "the ledger's figure, not a new measurement"
    end
  end

  test "an hour the meter failed to send is sent with the rest" do
    report(Time.utc(2026, 10, 12, 10), state: "failed", seconds: 7200)

    travel_to @now do
      assert_equal 7200, final_usage.billed[Time.utc(2026, 10, 12, 10)]
    end
  end

  # The hourly run never writes an hour for a stopped company.
  test "the hours measured here go into the company's ledger; the ones the meter measured are already there" do
    report(Time.utc(2026, 10, 12, 13), state: "reported", seconds: 3600)

    travel_to @now do
      final_usage.record!
    end

    assert_equal({ Time.utc(2026, 10, 12, 14) => 2 * 20 * 60 },
                 CompanyCapacityUsage.where(company: @company).to_h { |row| [ row.period_start.utc, row.quantity_seconds ] })
  end

  test "a company Aixle carries is measured and billed for nothing" do
    @company.update!(managed_by_aixle: true)

    travel_to @now do
      assert_empty final_usage.billed
    end
  end
end
