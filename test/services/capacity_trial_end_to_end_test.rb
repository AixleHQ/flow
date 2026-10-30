# frozen_string_literal: true

require "test_helper"

# The whole arc, in one place: a company spends its free capacity, the hourly
# meter notices, and the drain stops granting. Each half is tested on its own —
# this is the join, because a blocking rule nothing enforces and an enforcement
# nothing blocks both pass their own tests.
class CapacityTrialEndToEndTest < ActiveSupport::TestCase
  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))

    @user = create(:user, :with_company)
    @company = @user.companies.first
    # Ten before the trial, which brings it down to one; and a one-hour trial,
    # so the hour the meter closes below spends it exactly.
    with_company_limit(@company, 10)
    @company.update!(billing_state: "trialing", trial_hours: 1)
    @project = create(:project, owner: @user, company: @company)
  end

  def enqueue
    SessionAdmissionService.enqueue!(create(:terminal_session, user: @user, project: @project))
  end

  def meter_the_hour(hour)
    Billing::CapacityMeter.new(adapters: [ Billing::Meter::Null.new ], now: hour + 1.hour + 5.minutes).call
  end

  test "a company spends its free trial and stops" do
    # It asked for ten and runs one while the trial lasts.
    running, waiting, = 3.times.map { enqueue }
    assert_equal [ running.id ], SessionAdmissionService.drain!

    # An hour passes, and the meter closes it.
    hour = Time.current.utc.beginning_of_hour - 1.hour
    CompanyCapacityChange.record!(company_id: @company.id, max_sessions: 10, occurred_at: hour - 1.hour)
    meter_the_hour(hour)

    # Ours to read, and the sum the trial is spent from: an hour at the trial's
    # one worker is one worker-hour, which is the whole of this trial.
    assert_equal 3600, CompanyCapacityUsage.where(company: @company).sum(:quantity_seconds)
    assert @company.reload.billing_blocked?

    # And now the drain grants nothing, including what was already queued.
    SessionAdmissionService.cancel!(running.terminal_session)
    assert_empty SessionAdmissionService.drain!
    assert_nil waiting.reload.admitted_at
  end

  # The other half of the bargain: paying starts it again without anyone
  # re-queueing anything.
  test "moving the company on lets the queue drain again" do
    queued = enqueue
    @company.update!(billing_state: "blocked")
    assert_empty SessionAdmissionService.drain!

    @company.update!(billing_state: "active")

    assert_equal [ queued.id ], SessionAdmissionService.drain!
  end

  # A company nobody is billed for is not sent to a provider, but its hours are
  # still ours to count.
  test "the hours are recorded for us and sent to nobody" do
    hour = Time.current.utc.beginning_of_hour - 1.hour
    CompanyCapacityChange.record!(company_id: @company.id, max_sessions: 10, occurred_at: hour - 1.hour)

    meter_the_hour(hour)

    report = CapacityMeterReport.find_by(provider: Billing::Meter::Null.provider, period_start: hour)
    assert_equal 0, report.quantity_seconds, "a trialing company is invoiced for nothing"
    assert_empty report.breakdown
    assert_equal 3600, CompanyCapacityUsage.where(company: @company).sum(:quantity_seconds)
  end
end
