# frozen_string_literal: true

require "test_helper"

# An operator puts a company on a trial by naming its last day, from the admin.
class CompanyTrialTest < ActiveSupport::TestCase
  setup do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
    travel_to Time.utc(2026, 10, 30, 10)
  end

  def used!(company, hours)
    CompanyCapacityUsage.record!(
      company_id: company.id, period_start: Time.utc(2026, 10, 1, 10), quantity_seconds: hours * 3600
    )
  end

  test "a last day puts a company on a trial that ends with that day" do
    company = create(:company)

    company.update!(trial_last_day: Date.new(2026, 11, 15))

    assert company.billing_trialing?
    assert_equal Time.current, company.trial_started_at
    assert_equal Date.new(2026, 11, 15), Billing::Trial.last_day(company)
    assert_equal 17, Billing::Trial.days_left(company)
  end

  test "moving the last day of a trial under way keeps what it has spent" do
    company = create(:company, :trialing)
    used!(company, 100)

    company.update!(trial_last_day: Date.new(2026, 11, 15))

    assert_nil company.trial_started_at
    assert_equal 100 * 3600, Billing::Trial.used_seconds(company)
    assert_equal Date.new(2026, 11, 15), Billing::Trial.last_day(company)
  end

  test "a company whose trial ended can be given another" do
    company = create(:company, billing_state: "blocked", billing_block_reason: "allowance")
    used!(company, 720)

    company.update!(trial_last_day: Date.current)

    assert company.billing_trialing?
    assert_nil company.billing_block_reason
    assert_equal 0, Billing::Trial.used_seconds(company)
    assert_equal Date.current, Billing::Trial.last_day(company)
  end

  test "a company whose subscription has ended can be put on a trial" do
    company = create(:company, :subscribed, billing_state: "blocked", billing_block_reason: "canceled")

    company.update!(trial_last_day: Date.new(2026, 11, 15))

    assert company.billing_trialing?
  end

  # The ended subscription's id stays on the company, and must not read as one
  # that still bills.
  test "a trial that followed an ended subscription can still be moved" do
    company = create(:company, :subscribed, billing_state: "blocked", billing_block_reason: "canceled")
    company.update!(trial_last_day: Date.new(2026, 11, 15))

    company.update!(trial_last_day: Date.new(2026, 12, 1))
    assert_equal Date.new(2026, 12, 1), Billing::Trial.last_day(company)

    company.update!(billing_state: "blocked", billing_block_reason: "allowance")
    assert company.update(trial_last_day: Date.new(2026, 12, 15)), company.errors.full_messages.to_sentence
    assert company.billing_trialing?
  end

  test "a company that goes onto a trial drops to one worker" do
    company = create(:company, session_concurrency_limit: "4")

    company.update!(trial_last_day: Date.new(2026, 11, 15))

    assert_equal 1, SessionConcurrencyLimit.for_company(company.id)
  end

  test "moving the last day leaves a company given more before as it was" do
    company = create(:company, session_concurrency_limit: "4")
    company.update_column(:billing_state, "trialing")

    company.update!(trial_last_day: Date.new(2026, 11, 15), session_concurrency_limit: "4")

    assert_equal 4, SessionConcurrencyLimit.for_company(company.id)
  end

  test "saving anything else leaves the trial as it is" do
    company = create(:company, :trialing)

    assert_no_changes -> { company.reload.trial_hours } do
      travel 3.hours
      company.update!(display_name: "Acme")
    end
  end

  test "a trial is refused to a company a subscription still bills" do
    company = create(:company, :subscribed)

    assert_not company.update(trial_last_day: Date.new(2026, 11, 15))
    assert_match(/subscription bills this company/, company.errors[:trial_last_day].to_sentence)
    assert company.reload.billing_active?
  end

  test "a trial is refused to a company we carry" do
    company = create(:company, :managed_by_aixle)

    assert_not company.update(trial_last_day: Date.new(2026, 11, 15))
    assert_match(/untick Managed by Aixle/, company.errors[:trial_last_day].to_sentence)
  end

  test "a last day in the past is refused" do
    company = create(:company)

    assert_not company.update(trial_last_day: Date.yesterday)
    assert_match(/past/, company.errors[:trial_last_day].to_sentence)
  end

  test "outside the hosted product there are no trials to set" do
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SELF_HOSTED))
    company = create(:company)

    assert_not company.update(trial_last_day: Date.new(2026, 11, 15))
    assert company.reload.billing_active?
  end
end
