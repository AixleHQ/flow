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

  test "a company we carry is not billable" do
    paying = create(:company)
    ours = create(:company, :managed_by_aixle)

    assert_includes Company.billing_billable, paying
    assert_not_includes Company.billing_billable, ours
  end
end
