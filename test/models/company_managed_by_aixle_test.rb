# frozen_string_literal: true

require "test_helper"

# A company we carry pays nobody, so nothing about billing may stop it or bill it.
class CompanyManagedByAixleTest < ActiveSupport::TestCase
  test "a trialing company that becomes ours stops spending an allowance" do
    company = create(:company, :trialing)

    company.update!(managed_by_aixle: true)

    assert_equal "active", company.reload.billing_state
  end

  test "a blocked company that becomes ours runs again, without its block reason" do
    company = create(:company, billing_state: "blocked", billing_block_reason: "allowance",
                               billing_unpaid_invoice_url: "https://invoice.stripe.test/1")

    company.update!(managed_by_aixle: true)

    company.reload
    assert_equal "active", company.billing_state
    assert_nil company.billing_block_reason
    assert_nil company.billing_unpaid_invoice_url
  end

  # What the trial job and a payment-failed webhook do to any company.
  test "a company we carry cannot be blocked" do
    company = create(:company, :managed_by_aixle)

    company.update!(billing_state: "blocked", billing_block_reason: "payment_failed")

    assert_equal "active", company.reload.billing_state
  end

  test "a company we stop carrying starts on the allowance" do
    saas!
    company = managed_company

    company.update!(managed_by_aixle: false)

    assert_equal "trialing", company.reload.billing_state
  end

  # The allowance counts every hour the company was offered, ours included.
  test "a company we stop carrying that already ran past the allowance is stopped until it adds a card" do
    saas!
    Settings.stubs(:trial).returns(Hashie::Mash.new(queue_hours: 1))
    company = managed_company
    CompanyCapacityUsage.record!(company_id: company.id, period_start: Time.utc(2026, 9, 29, 10),
                                 quantity_seconds: 3600)

    company.update!(managed_by_aixle: false)

    company.reload
    assert_equal "blocked", company.billing_state
    assert_equal "allowance", company.billing_status
  end

  test "a company we stop carrying keeps paying through the subscription it already had" do
    saas!
    company = managed_company(stripe_customer_id: "cus_test_1", stripe_subscription_id: "sub_test_1")

    company.update!(managed_by_aixle: false)

    assert_equal "active", company.reload.billing_state
  end

  # What the deleted webhook does to a company we carry: the block is dropped,
  # the end date stays.
  test "a company we stop carrying whose subscription ended needs a new card" do
    saas!
    company = managed_company(stripe_customer_id: "cus_test_1", stripe_subscription_id: "sub_test_1")
    company.update!(billing_state: "blocked", billing_block_reason: "canceled", billing_cancels_at: 1.day.ago)

    company.update!(managed_by_aixle: false)

    assert_equal "canceled", company.reload.billing_status
  end

  test "a company we stop carrying keeps a cancellation that has not happened yet" do
    saas!
    company = managed_company(stripe_customer_id: "cus_test_1", stripe_subscription_id: "sub_test_1",
                              billing_cancels_at: 1.week.from_now)

    company.update!(managed_by_aixle: false)

    assert_equal "cancelling", company.reload.billing_status
  end

  test "a company we stop carrying needs a limit to be metered against" do
    saas!
    company = create(:company, :managed_by_aixle)

    assert_not company.update(managed_by_aixle: false)
    assert_includes company.errors[:session_concurrency_limit], Company::UNBOUNDED_PAYING_COMPANY
    assert company.reload.managed_by_aixle
  end

  test "outside the hosted product a company we stop carrying stays as it was" do
    company = create(:company, :managed_by_aixle)

    company.update!(managed_by_aixle: false)

    assert_equal "active", company.reload.billing_state
  end

  test "a company we carry is not billable" do
    paying = create(:company)
    ours = create(:company, :managed_by_aixle)

    assert_includes Company.billing_billable, paying
    assert_not_includes Company.billing_billable, ours
  end

  private

  def saas!
    Settings.stubs(:deployment).returns(Hashie::Mash.new(mode: Deployment::SAAS))
  end

  def managed_company(**attributes)
    create(:company, :managed_by_aixle, session_concurrency_limit: "2", **attributes)
  end
end
