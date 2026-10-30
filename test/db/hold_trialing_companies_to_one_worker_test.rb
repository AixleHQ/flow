# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261030130000_hold_trialing_companies_to_one_worker")

class HoldTrialingCompaniesToOneWorkerTest < ActiveSupport::TestCase
  setup { Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS)) }

  def migrate
    migration = HoldTrialingCompaniesToOneWorker.new
    migration.suppress_messages { migration.up }
  end

  # A company as it stood before the rule: on the trial at the number it typed.
  def company_from_before(billing_state, limit, block_reason: nil, **attributes)
    limit_attributes = limit ? { session_concurrency_limit: limit.to_s } : {}
    company = create(:company, **limit_attributes, **attributes)
    company.update_columns(billing_state: billing_state, billing_block_reason: block_reason)
    company
  end

  def logged(company) = CompanyCapacityChange.where(company_id: company.id).order(:occurred_at, :id).last&.max_sessions

  test "a trialing company drops to one worker, and the meter's log says so" do
    company = company_from_before("trialing", 5)

    migrate
    migrate

    assert_equal 1, SessionConcurrencyLimit.for_company(company.id)
    assert_equal 1, logged(company)
    assert_equal 1, CompanyCapacityChange.where(company_id: company.id, max_sessions: 1).count
  end

  test "so does one stopped at the end of its trial" do
    company = company_from_before("blocked", 3, block_reason: "allowance")

    migrate

    assert_equal 1, SessionConcurrencyLimit.for_company(company.id)
    assert_equal 1, logged(company)
  end

  test "a trialing company with no limit at all is given one" do
    company = company_from_before("trialing", nil)

    migrate

    row = SessionConcurrencyLimit.find_by(scope_type: "Company", scope_id: company.id)
    assert_equal 1, row.max_sessions
    assert_equal company.id, row.company_id
    assert_equal 1, logged(company)
  end

  test "one already on one worker is left alone" do
    company = company_from_before("trialing", 1)

    assert_no_difference -> { CompanyCapacityChange.where(company_id: company.id).count } do
      migrate
    end
  end

  test "a company that pays, has a subscription to settle or is ours keeps its number" do
    paying = company_from_before("active", 5)
    ended = company_from_before("blocked", 4, block_reason: "canceled")
    unpaid = company_from_before("blocked", 4, block_reason: "payment_failed")
    ours = create(:company, :managed_by_aixle, session_concurrency_limit: "6")

    migrate

    assert_equal [ 5, 4, 4, 6 ], [ paying, ended, unpaid, ours ].map { |c| SessionConcurrencyLimit.for_company(c.id) }
  end

  test "nothing changes outside the hosted product" do
    company = company_from_before("trialing", 5)
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SELF_HOSTED))

    migrate

    assert_equal 5, SessionConcurrencyLimit.for_company(company.id)
  end
end
