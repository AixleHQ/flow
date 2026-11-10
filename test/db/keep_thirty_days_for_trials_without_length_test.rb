# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261109100000_keep_thirty_days_for_trials_without_length")

class KeepThirtyDaysForTrialsWithoutLengthTest < ActiveSupport::TestCase
  setup { Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS)) }

  def migrate
    migration = KeepThirtyDaysForTrialsWithoutLength.new
    migration.suppress_messages { migration.up }
  end

  # A company whose trial began before trials kept their length.
  def company_from_before(billing_state, block_reason: nil)
    company = create(:company)
    company.update_columns(billing_state: billing_state, billing_block_reason: block_reason, trial_hours: nil)
    company
  end

  test "a trial without a length keeps thirty days, not the new default" do
    company = company_from_before("trialing")

    migrate

    assert_equal 720, company.reload.trial_hours
    assert_equal 720 * 3600, Billing::Trial.allowance_seconds(company)
  end

  # Already past fourteen days: on the new default the next hourly check would
  # stop it.
  test "one that has run past fourteen days is not stopped by the change" do
    company = company_from_before("trialing")
    CompanyCapacityUsage.record!(company_id: company.id, period_start: 20.days.ago.beginning_of_hour,
                                 quantity_seconds: 20 * 24 * 3600)

    migrate

    assert_empty Billing::Trial.enforce!
    assert company.reload.billing_trialing?
  end

  test "a trial that has its own length keeps it" do
    company = create(:company, :trialing)
    company.update_columns(trial_hours: 100)

    migrate

    assert_equal 100, company.reload.trial_hours
  end

  test "a company not on a trial is left alone" do
    paying = company_from_before("active")
    stopped = company_from_before("blocked", block_reason: "allowance")

    migrate

    assert_equal [ nil, nil ], [ paying, stopped ].map { |c| c.reload.trial_hours }
  end

  test "nothing changes outside the hosted product" do
    company = company_from_before("trialing")
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SELF_HOSTED))

    migrate

    assert_nil company.reload.trial_hours
  end
end
