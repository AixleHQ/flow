# frozen_string_literal: true

require "test_helper"

# Deleting a company is what the admin's delete button does, and every table
# that points at `companies` decides whether it still can. Two added on the
# Marketplace branch did not, which no test noticed because nothing else here
# deletes one.
class CompanyDeletionTest < ActiveSupport::TestCase
  test "a company whose billing state has ever changed can still be deleted" do
    company = create(:company, billing_state: "trialing")
    company.update!(billing_state: "blocked", billing_block_reason: "allowance")

    assert_operator CompanyBillingStateChange.where(company_id: company.id).count, :>, 0,
                    "the log has to hold a row for this to be the case under test"

    company.destroy!

    assert_not Company.exists?(company.id)
    assert_empty CompanyBillingStateChange.where(company_id: company.id),
                 "the log is worth exactly as much as the company it describes"
  end

  test "a company a subscription was offered to can still be deleted, and the licence outlives it" do
    company = create(:company)
    license = create(:marketplace_license, :active, proposed_company: company, proposal_state: "pending")

    company.destroy!

    assert_not Company.exists?(company.id)
    assert_nil license.reload.proposed_company_id,
               "the offer lapses with the company; the subscription does not"
  end
end
