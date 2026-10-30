# frozen_string_literal: true

require "test_helper"

class Billing::TrialTest < ActiveSupport::TestCase
  setup do
    saas!
    @company = create(:company, :trialing)
  end

  def saas!(mode = Deployment::SAAS)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: mode))
  end

  def used!(hours, at: Time.utc(2026, 9, 29, 10))
    CompanyCapacityUsage.record!(
      company_id: @company.id, period_start: at, quantity_seconds: (hours * 3600).to_i
    )
  end

  def trial_days!(days)
    Settings.stubs(:trial).returns(Hashie::Mash.new(days: days))
  end

  test "a trial is thirty days unless the installation says otherwise" do
    assert_equal 30, Billing::Trial.days
    assert_equal 720, Billing::Trial.default_hours
  end

  test "a new trial is as long as the installation says" do
    trial_days!(14)

    assert_equal 336, create(:company, :trialing).trial_hours
  end

  # A trial promised thirty days stays thirty days.
  test "a company keeps the length of the trial it started" do
    trial_days!(7)

    assert_equal 720 * 3600, Billing::Trial.allowance_seconds(@company)
  end

  test "a trial from before lengths were kept follows the default" do
    @company.update_column(:trial_hours, nil)
    trial_days!(10)

    assert_equal 240 * 3600, Billing::Trial.allowance_seconds(@company)
  end

  test "a fresh company has the whole trial" do
    assert_equal 720 * 3600, Billing::Trial.remaining_seconds(@company)
    assert_equal 30, Billing::Trial.days_left(@company)
    assert_equal 30, Billing::Trial.length_in_days(@company)
    assert_not Billing::Trial.exhausted?(@company)
  end

  # The spend is a sum over the usage log rather than a counter beside it, so
  # there is nothing that can drift from what was actually offered.
  test "what it has spent is the sum of the hours it was offered" do
    used!(30, at: Time.utc(2026, 9, 29, 10))
    used!(20, at: Time.utc(2026, 9, 29, 11))

    assert_equal 50 * 3600, Billing::Trial.used_seconds(@company)
    assert_equal 670 * 3600, Billing::Trial.remaining_seconds(@company)
  end

  # An operator restarting a company by hand gives it a new trial; what it
  # spent before that is not held against it.
  test "a new trial counts only what was used since it began" do
    used!(80, at: Time.utc(2026, 9, 29, 10))
    used!(3, at: Time.utc(2026, 10, 5, 10))
    @company.update!(trial_started_at: Time.utc(2026, 10, 1))

    assert_equal 3 * 3600, Billing::Trial.used_seconds(@company)
  end

  test "a part of a day left counts as a day" do
    used!(720 - 25)

    assert_equal 2, Billing::Trial.days_left(@company)
  end

  # One worker spends an hour of the trial an hour, so what is left is also
  # when it ends.
  test "the last day is when what is left runs out" do
    used!(720 - 25)

    travel_to Time.utc(2026, 10, 30, 10) do
      assert_equal Date.new(2026, 10, 31), Billing::Trial.last_day(@company)
    end
  end

  test "a trial set to end with a day lasts until that day's end and no further" do
    travel_to Time.utc(2026, 10, 30, 10) do
      hours = Billing::Trial.hours_ending_on(Date.new(2026, 11, 2), spent_seconds: 10 * 3600)

      assert_equal 10 + 85, hours, "what was spent, then 3 days and 13 whole hours"
      assert_equal Date.new(2026, 11, 2), (Time.current + (hours - 10).hours).to_date
    end
  end

  test "spending the trial exactly is spending it" do
    used!(720)

    assert Billing::Trial.exhausted?(@company)
    assert_equal 0, Billing::Trial.remaining_seconds(@company)
    assert_equal 0, Billing::Trial.days_left(@company)
  end

  test "remaining never goes below nothing" do
    used!(720 + 40)

    assert_equal 0, Billing::Trial.remaining_seconds(@company)
  end

  test "enforce stops a company that has spent it" do
    used!(720)

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
    CompanyCapacityUsage.record!(
      company_id: paying.id, period_start: Time.utc(2026, 9, 29, 10), quantity_seconds: 720 * 3600 * 10
    )

    assert_empty Billing::Trial.enforce!
    assert paying.reload.billing_active?
  end

  # A self-hosted operator pays nobody and a Marketplace customer bought their
  # capacity from AWS, so neither has a trial to run out of.
  test "nothing is enforced outside the hosted product" do
    used!(720)
    saas!(Deployment::SELF_HOSTED)

    assert_empty Billing::Trial.enforce!
    assert @company.reload.billing_trialing?
  end

  test "a trialing company runs one worker and a blocked one none" do
    assert_equal 1, Billing::Trial.ceiling_for("trialing")
    assert_equal 0, Billing::Trial.ceiling_for("blocked")
    assert_nil Billing::Trial.ceiling_for("active")
  end

  test "applies only where we host" do
    assert Billing::Trial.applies?(@company)

    saas!(Deployment::AWS_MARKETPLACE)
    assert_not Billing::Trial.applies?(@company)
  end
end
