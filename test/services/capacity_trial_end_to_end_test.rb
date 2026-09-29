# frozen_string_literal: true

require "test_helper"

# The whole arc, in one place: a company spends its free capacity, the hourly
# meter notices, and the drain stops granting. Each half is tested on its own —
# this is the join, because a blocking rule nothing enforces and an enforcement
# nothing blocks both pass their own tests.
class CapacityTrialEndToEndTest < ActiveSupport::TestCase
  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    # Ten queue-hours of allowance against a limit of ten, so one hour spends it
    # exactly — which is the point: the limit sets the rate.
    Settings.stubs(:trial).returns(Hashie::Mash.new(queue_hours: 10))

    @user = create(:user, :with_company)
    @company = @user.companies.first
    @company.update!(billing_state: "trialing")
    @project = create(:project, owner: @user, company: @company)
    with_company_limit(@company, 10)
  end

  def enqueue
    SessionAdmissionService.enqueue!(create(:terminal_session, user: @user, project: @project))
  end

  def meter_the_hour(hour)
    Billing::CapacityMeter.new(adapter: Billing::Meter::Null.new, now: hour + 1.hour + 5.minutes).call
  end

  test "a company spends its free capacity and stops" do
    # It runs the ten it asked for; nothing is capped while the allowance lasts.
    running = 3.times.map { enqueue }
    assert_equal running.map(&:id), SessionAdmissionService.drain!

    # An hour passes at that capacity, and the meter closes it.
    hour = Time.current.utc.beginning_of_hour - 1.hour
    CompanyCapacityChange.record!(company_id: @company.id, max_sessions: 10, occurred_at: hour - 1.hour)
    meter_the_hour(hour)

    # Ours to read, and the sum the allowance is spent from: an hour at ten is
    # ten queue-hours, which is the whole of a ten-hour allowance.
    assert_equal 10 * 3600, CompanyCapacityUsage.total_seconds_for(@company.id)
    assert @company.reload.billing_blocked?

    # And now the drain grants nothing, including what was already queued.
    queued = enqueue
    running.each { |admission| SessionAdmissionService.cancel!(admission.terminal_session) }
    assert_empty SessionAdmissionService.drain!
    assert_nil queued.reload.admitted_at
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
    assert_equal 10 * 3600, CompanyCapacityUsage.total_seconds_for(@company.id)
  end
end
