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

  # The callback is the only writer, so a write that went round it -- a pod
  # on the previous release during a deploy, a console -- leaves the row and
  # the log disagreeing until the next logged change. The meter brings the
  # log back to the row every hour, dated then: when the row changed is what
  # nobody knows.
  test "reconciling logs a state the callback never saw, dated now" do
    company = create(:company, billing_state: "active")
    company.update_columns(billing_state: "blocked", billing_block_reason: "canceled")
    now = Time.utc(2026, 10, 28, 11, 5)

    assert_equal 1, CompanyBillingStateChange.reconcile!(now: now)

    last = CompanyBillingStateChange.where(company_id: company.id).order(:id).last
    assert_equal "blocked", last.billing_state
    assert_equal now, last.occurred_at
  end

  test "reconciling leaves a log that agrees with its rows alone" do
    create(:company, billing_state: "active")
    create(:company, billing_state: "trialing")

    assert_equal 0, CompanyBillingStateChange.reconcile!
    assert_equal 2, CompanyBillingStateChange.count
  end

  test "reconciling gives a company the log does not know its first entry" do
    company = create(:company)
    CompanyBillingStateChange.where(company_id: company.id).delete_all

    assert_equal 1, CompanyBillingStateChange.reconcile!
    assert_equal [ company.billing_state ],
                 CompanyBillingStateChange.where(company_id: company.id).map(&:billing_state)
  end

  test "saving without touching the state logs nothing" do
    company = create(:company)
    company.update!(name: "Renamed")

    assert_equal 1, CompanyBillingStateChange.where(company_id: company.id).count
  end
end
