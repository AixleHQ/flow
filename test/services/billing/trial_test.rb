# frozen_string_literal: true

require "test_helper"

class Billing::TrialTest < ActiveSupport::TestCase
  # A company that signs up at 10:00 on Oct 30 gets thirty days, Oct 30 to the
  # end of Nov 28: 29 days and 13 whole hours.
  SIGNUP = Time.utc(2026, 10, 30, 10)
  LENGTH = (29 * 24) + 13

  setup do
    saas!
    travel_to SIGNUP
    @company = create(:company, :trialing)
  end

  def saas!(mode = Deployment::SAAS)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
  end

  # What the hourly meter writes: one row per closed hour the company was
  # offered anything.
  def metered!(company, hours, from:)
    CompanyCapacityUsage.insert_all(
      Array.new(hours) { |offset| { company_id: company.id, period_start: from + offset.hours, quantity_seconds: 3600 } }
    )
  end

  def used!(hours, at: SIGNUP)
    CompanyCapacityUsage.record!(company_id: @company.id, period_start: at, quantity_seconds: hours * 3600)
  end

  def trial_days!(days)
    Settings.stubs(:trial).returns(Hashie::Mash.new(days: days))
  end

  test "a trial is thirty days unless the installation says otherwise" do
    assert_equal 30, Billing::Trial.days
    assert_equal 720, Billing::Trial.default_hours
  end

  # Today is the first day, and the trial ends with the last one's end — the
  # same end an operator's last day has.
  test "a new trial runs to the end of its last day" do
    assert_equal LENGTH, @company.trial_hours
    assert_equal Date.new(2026, 11, 28), Billing::Trial.last_day(@company)
    assert_equal 30, Billing::Trial.days_left(@company)
    assert_equal 30, Billing::Trial.length_in_days(@company)
  end

  test "a new trial is as long as the installation says" do
    trial_days!(14)

    assert_equal (13 * 24) + 13, create(:company, :trialing).trial_hours
  end

  # A trial promised thirty days stays thirty days.
  test "a company keeps the length of the trial it started" do
    trial_days!(7)

    assert_equal LENGTH * 3600, Billing::Trial.allowance_seconds(@company)
  end

  test "a trial from before lengths were kept follows the default" do
    @company.update_column(:trial_hours, nil)
    trial_days!(10)

    assert_equal 240 * 3600, Billing::Trial.allowance_seconds(@company)
  end

  # The meter lags the clock by the hour under way and counts the hour a trial
  # began in as a part hour, so what is left is counted on from where it got
  # to. Counted from now, a trial ending at 23:40 would show the day after as
  # its last.
  test "the last day holds while the meter counts the hours" do
    travel 40.minutes
    company = create(:company, :trialing)
    CompanyCapacityUsage.record!(company_id: company.id, period_start: SIGNUP, quantity_seconds: 20 * 60)

    metered!(company, 47, from: SIGNUP + 1.hour)
    travel_to SIGNUP + 2.days + 55.minutes

    assert_equal Date.new(2026, 11, 28), Billing::Trial.last_day(company)
    assert_equal 28, Billing::Trial.days_left(company)

    metered!(company, 708 - 47, from: SIGNUP + 48.hours)
    travel_to Time.utc(2026, 11, 28, 23, 20)

    assert_equal Date.new(2026, 11, 28), Billing::Trial.last_day(company)
    assert_equal 1, Billing::Trial.days_left(company)
  end

  # The meter writes whole hours, so a trial that began at 10:40 begins in the
  # 10:00 row.
  test "the hour a trial began in counts towards it" do
    @company.update!(trial_started_at: SIGNUP + 40.minutes)
    used!(1, at: SIGNUP - 1.hour)
    CompanyCapacityUsage.record!(company_id: @company.id, period_start: SIGNUP, quantity_seconds: 20 * 60)

    assert_equal 20 * 60, Billing::Trial.used_seconds(@company)
  end

  # The spend is a sum over the usage log rather than a counter beside it, so
  # there is nothing that can drift from what was actually offered.
  test "what it has spent is the sum of the hours it was offered" do
    used!(30, at: SIGNUP)
    used!(20, at: SIGNUP + 1.hour)

    assert_equal 50 * 3600, Billing::Trial.used_seconds(@company)
    assert_equal (LENGTH - 50) * 3600, Billing::Trial.remaining_seconds(@company)
  end

  # An operator restarting a company by hand gives it a new trial; what it
  # spent before that is not held against it.
  test "a new trial counts only what was used since it began" do
    used!(80, at: Time.utc(2026, 9, 29, 10))
    used!(3, at: Time.utc(2026, 10, 5, 10))
    @company.update!(trial_started_at: Time.utc(2026, 10, 1))

    assert_equal 3 * 3600, Billing::Trial.used_seconds(@company)
  end

  test "a trial set to end with a day lasts until that day's end and no further" do
    hours = Billing::Trial.hours_ending_on(Date.new(2026, 11, 2), spent_seconds: 10 * 3600, from: SIGNUP)

    assert_equal 10 + 85, hours, "what was spent, then 3 days and 13 whole hours"
    assert_equal Date.new(2026, 11, 2), (SIGNUP + (hours - 10).hours).to_date
  end

  test "spending the trial exactly is spending it" do
    used!(LENGTH)

    assert Billing::Trial.exhausted?(@company)
    assert_equal 0, Billing::Trial.remaining_seconds(@company)
    assert_equal 0, Billing::Trial.days_left(@company)
  end

  test "remaining never goes below nothing" do
    used!(LENGTH + 40)

    assert_equal 0, Billing::Trial.remaining_seconds(@company)
  end

  test "enforce stops a company that has spent it" do
    used!(LENGTH)

    assert_equal [ @company.id ], Billing::Trial.enforce!

    assert @company.reload.billing_blocked?
    assert_equal "allowance", @company.billing_status
  end

  test "enforce leaves a company that has not" do
    used!(10)

    assert_empty Billing::Trial.enforce!
    assert @company.reload.billing_trialing?
  end

  test "enforce stops a company at the length of its own trial" do
    @company.update!(trial_hours: 48)
    used!(48)

    assert_equal [ @company.id ], Billing::Trial.enforce!
  end

  # A company someone is paying for has no trial to spend, whatever its usage
  # says.
  test "enforce leaves a paying company alone" do
    paying = create(:company)
    CompanyCapacityUsage.record!(company_id: paying.id, period_start: SIGNUP, quantity_seconds: 7200 * 3600)

    assert_empty Billing::Trial.enforce!
    assert paying.reload.billing_active?
  end

  # A self-hosted operator pays nobody and a Marketplace customer bought their
  # capacity from AWS, so neither has a trial to run out of.
  test "nothing is enforced outside the hosted product" do
    used!(LENGTH)
    saas!(Deployment::SELF_HOSTED)

    assert_empty Billing::Trial.enforce!
    assert @company.reload.billing_trialing?
  end

  test "a trialing company runs one worker and a blocked one none" do
    assert_equal 1, Billing::Trial.ceiling_for("trialing")
    assert_equal 0, Billing::Trial.ceiling_for("blocked")
    assert_nil Billing::Trial.ceiling_for("active")
  end

  # Nobody has paid yet, on the trial or once it has ended, so there is no
  # number of workers to choose.
  test "the workers are fixed until a card is added" do
    assert Billing::Trial.workers_fixed?(@company)

    @company.update!(billing_state: "blocked", billing_block_reason: "allowance")
    assert Billing::Trial.workers_fixed?(@company)

    @company.update!(billing_block_reason: "payment_failed")
    assert_not Billing::Trial.workers_fixed?(@company)

    @company.update!(billing_state: "active")
    assert_not Billing::Trial.workers_fixed?(@company)
  end

  test "applies only where we host" do
    assert Billing::Trial.applies?(@company)

    saas!(Deployment::AWS_MARKETPLACE)
    assert_not Billing::Trial.applies?(@company)
  end
end
