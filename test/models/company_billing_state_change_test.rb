# frozen_string_literal: true

require "test_helper"

# The log Billing::CapacityWindow reads to tell an hour a workspace was stopped
# for from one it was running. Its value rests on there being no live company
# missing from it: a company the log does not know is read from its live row,
# which is the snapshot the log exists to stop trusting.
class CompanyBillingStateChangeTest < ActiveSupport::TestCase
  test "a company is in the log from the moment it exists" do
    company = create(:company)

    entries = CompanyBillingStateChange.where(company_id: company.id).order(:occurred_at)

    assert_equal [ company.billing_state ], entries.map(&:billing_state)
  end

  test "each change appends, so an hour can be read against the state it was in" do
    company = create(:company, billing_state: "trialing")
    company.update!(billing_state: "blocked", billing_block_reason: "allowance")
    company.update!(billing_state: "active", billing_block_reason: nil)

    assert_equal %w[trialing blocked active],
                 CompanyBillingStateChange.where(company_id: company.id).order(:id).map(&:billing_state)
  end

  test "a change that is rolled back is not logged" do
    company = create(:company, billing_state: "trialing")

    ActiveRecord::Base.transaction do
      company.update!(billing_state: "active")
      raise ActiveRecord::Rollback
    end

    assert_equal %w[trialing], CompanyBillingStateChange.where(company_id: company.id).order(:id).map(&:billing_state),
                 "the measurement reads this for an hour that has closed; an entry for a state that never " \
                 "happened would bill against it"
  end

  test "saving without touching the state logs nothing" do
    company = create(:company)
    company.update!(name: "Renamed")

    assert_equal 1, CompanyBillingStateChange.where(company_id: company.id).count
  end
end
