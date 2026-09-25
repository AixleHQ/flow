# frozen_string_literal: true

require "test_helper"

class Billing::CapacityMeterTest < ActiveSupport::TestCase
  # A real adapter implementing the real interface, so the meter is exercised
  # through the seam every provider goes through rather than a stub of itself.
  class RecordingAdapter < Billing::Meter::Base
    attr_reader :delivered

    def self.provider = "recording"

    def initialize(fail_times: 0)
      super()
      @delivered = []
      @fail_times = fail_times
    end

    def deliver(report)
      if @fail_times.positive?
        @fail_times -= 1
        raise Billing::Meter::Base::Unavailable, "provider is down"
      end

      @delivered << report.period_start
      "external-#{report.period_start.to_i}"
    end
  end

  setup do
    @now = Time.utc(2026, 9, 23, 11, 5)
    @company = create(:company)
    CompanyCapacityChange.record!(company_id: @company.id, max_sessions: 12, occurred_at: @now - 3.hours)
  end

  def meter(adapter: RecordingAdapter.new, now: @now)
    Billing::CapacityMeter.new(adapter: adapter, now: now)
  end

  def report_for(hour) = CapacityMeterReport.find_by(provider: "recording", period_start: hour)

  # The tests below define the whole installation's capacity themselves, so the
  # company `setup` gave a limit to must not be counted alongside it.
  def only_capacity_declared_here!
    SessionConcurrencyLimit.for_companies.delete_all
    CompanyCapacityChange.delete_all
  end

  test "the closed hour is measured and sent" do
    adapter = RecordingAdapter.new

    result = meter(adapter: adapter).call

    closed_hour = Time.utc(2026, 9, 23, 10)
    assert_equal [ closed_hour ], adapter.delivered
    assert_equal 1, result[:sent]
    report = report_for(closed_hour)
    assert_equal "reported", report.state
    assert_equal BigDecimal("720"), report.quantity_minutes, "twelve queues for a whole hour"
    assert_equal 12, report.peak_concurrent
  end

  test "a second pass over the same hour sends nothing twice" do
    adapter = RecordingAdapter.new
    meter(adapter: adapter).call

    meter(adapter: adapter).call

    assert_equal 1, adapter.delivered.size, "an hour already reported must never be sent again"
  end

  # The whole reason measuring and sending are separate steps.
  test "a provider failure keeps the measurement and retries it next run" do
    failing = RecordingAdapter.new(fail_times: 1)
    meter(adapter: failing).call

    closed_hour = Time.utc(2026, 9, 23, 10)
    assert_equal "failed", report_for(closed_hour).state
    assert_equal 1, report_for(closed_hour).attempts

    recovered = RecordingAdapter.new
    meter(adapter: recovered, now: @now + 1.hour).call

    assert_includes recovered.delivered, closed_hour
    assert_equal "reported", report_for(closed_hour).state
  end

  # Past six hours AWS will not accept the record whatever we do, so a ledger
  # that kept retrying it would be a list nobody can act on.
  test "an hour past the replay window is abandoned rather than retried" do
    stale = Time.utc(2026, 9, 23, 1)
    CapacityMeterReport.create!(provider: "recording", period_start: stale, quantity_seconds: 300, state: "failed")
    adapter = RecordingAdapter.new

    meter(adapter: adapter).call

    assert_equal "skipped", CapacityMeterReport.find_by(provider: "recording", period_start: stale).state
    assert_not_includes adapter.delivered, stale
  end

  # End to end, through the real write path: setting a limit is what records the
  # change, and the hourly run is what turns those into a quantity. The tests in
  # capacity_window_test cover the arithmetic on hand-written log rows; this one
  # covers the wiring between them, which is where a silent regression would sit.
  test "a limit raised and lowered inside one hour is metered at its peak" do
    hour = Time.utc(2026, 9, 23, 10)
    company = create(:company)
    only_capacity_declared_here!

    travel_to(hour - 1.hour) { SessionConcurrencyLimit.set!(scope: company, max_sessions: 4) }
    travel_to(hour + 20.minutes) { SessionConcurrencyLimit.set!(scope: company, max_sessions: 40) }
    travel_to(hour + 40.minutes) { SessionConcurrencyLimit.set!(scope: company, max_sessions: 4) }

    adapter = RecordingAdapter.new
    Billing::CapacityMeter.new(adapter: adapter, now: hour + 1.hour + 5.minutes).call

    report = CapacityMeterReport.find_by(provider: "recording", period_start: hour)
    # 20 min at 4, 20 min at 40, 20 min at 4 = 80 + 800 + 80
    assert_equal BigDecimal("960"), report.quantity_minutes,
      "a sample at the end of the hour would have said 4 the whole way"
    assert_equal 40, report.peak_concurrent
    assert_equal "reported", report.state
    assert_equal [ hour ], adapter.delivered
  end

  # The hour after the burst is billed at what the company actually has, so the
  # peak is not carried forward.
  test "the hour after a burst is metered at the limit that survived it" do
    hour = Time.utc(2026, 9, 23, 10)
    company = create(:company)
    only_capacity_declared_here!

    travel_to(hour - 1.hour) { SessionConcurrencyLimit.set!(scope: company, max_sessions: 4) }
    travel_to(hour + 20.minutes) { SessionConcurrencyLimit.set!(scope: company, max_sessions: 40) }
    travel_to(hour + 40.minutes) { SessionConcurrencyLimit.set!(scope: company, max_sessions: 4) }

    adapter = RecordingAdapter.new
    Billing::CapacityMeter.new(adapter: adapter, now: hour + 2.hours + 5.minutes).call

    next_hour = CapacityMeterReport.find_by(provider: "recording", period_start: hour + 1.hour)
    assert_equal BigDecimal("240"), next_hour.quantity_minutes, "four for a whole hour, and the burst is not carried"
  end

  # Two organisations moving in the same hour: the installation is billed for the
  # most it ever offered at once, not for the sum of what each peaked at.
  test "two companies changing in the same hour are metered on the running total" do
    hour = Time.utc(2026, 9, 23, 10)
    acme = create(:company)
    globex = create(:company)
    only_capacity_declared_here!

    travel_to(hour - 1.hour) do
      SessionConcurrencyLimit.set!(scope: acme, max_sessions: 10)
      SessionConcurrencyLimit.set!(scope: globex, max_sessions: 10)
    end
    travel_to(hour + 15.minutes) { SessionConcurrencyLimit.set!(scope: acme, max_sessions: 30) }
    travel_to(hour + 45.minutes) { SessionConcurrencyLimit.set!(scope: globex, max_sessions: 2) }

    Billing::CapacityMeter.new(adapter: RecordingAdapter.new, now: hour + 1.hour + 5.minutes).call

    report = CapacityMeterReport.find_by(provider: "recording", period_start: hour)
    # acme: 15 min at 10 + 45 at 30 = 1500. globex: 45 min at 10 + 15 at 2 = 480.
    assert_equal BigDecimal("1980"), report.quantity_minutes
    assert_equal 40, report.peak_concurrent, "30 + 10 was the most offered at one time, and is not the bill"
    assert_equal({ acme.id.to_s => 90_000, globex.id.to_s => 28_800 }, report.breakdown)
  end

  # AWS takes an Integer, so this is the only place a fraction is lost — and it
  # is lost downward, because charging for a minute that was not given is worse
  # than giving away one that was.
  test "the AWS adapter rounds the quantity down" do
    report = CapacityMeterReport.new(period_start: Time.utc(2026, 9, 23, 10),
                                     quantity_seconds: 359, breakdown: { "1" => 359 })

    assert_equal 5, Billing::Meter::AwsMarketplace.new.quantity_for(report),
      "5.98 queue-minutes is sent as 5, never 6"
  end

  # AWS refuses a record whose allocations do not sum to the quantity, so the
  # split has to absorb its own rounding rather than each part rounding alone.
  test "the AWS allocations add up to exactly what is metered" do
    report = CapacityMeterReport.new(
      period_start: Time.utc(2026, 9, 23, 10),
      quantity_seconds: 600,
      breakdown: { "1" => 210, "2" => 210, "3" => 180 }
    )
    adapter = Billing::Meter::AwsMarketplace.new

    allocations = adapter.allocations_for(report)

    assert_equal adapter.quantity_for(report), allocations.values.sum
  end

  test "each deployment mode meters through its own provider" do
    assert_instance_of Billing::Meter::Null, Billing::CapacityMeter.adapter_for(Deployment::SELF_HOSTED)
    assert_instance_of Billing::Meter::Stripe, Billing::CapacityMeter.adapter_for(Deployment::SAAS)
    assert_instance_of Billing::Meter::AwsMarketplace, Billing::CapacityMeter.adapter_for(Deployment::AWS_MARKETPLACE)
  end

  # Both real adapters are stubs today, so the contract they have to keep is
  # narrow: answer with an identifier, never swallow a rejection silently.
  test "the shipped adapters answer with an identifier for the hour" do
    report = CapacityMeterReport.new(period_start: Time.utc(2026, 9, 23, 10), quantity_seconds: 180,
                                     breakdown: { "1" => 180 })

    assert_match(/2026-09-23T10:00:00Z/, Billing::Meter::Stripe.new.deliver(report))
    assert_match(/2026-09-23T10:00:00Z/, Billing::Meter::AwsMarketplace.new.deliver(report))
    assert_match(/2026-09-23T10:00:00Z/, Billing::Meter::Null.new.deliver(report))
  end
end
