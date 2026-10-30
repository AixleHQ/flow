# frozen_string_literal: true

class LetACompanyBeDeletedAgain < ActiveRecord::Migration[8.1]
  # Two foreign keys added on this branch refused `DELETE FROM companies`,
  # which is what the admin's delete button runs. The state log is worth as
  # much as the company it describes, like `company_capacity_changes`, so it
  # cascades; a licence proposed to a company that goes away is simply no
  # longer being asked, so it nullifies. A separate migration because the two
  # that added them have run on staging.
  def up
    remove_foreign_key :company_billing_state_changes, :companies
    add_foreign_key :company_billing_state_changes, :companies, on_delete: :cascade

    remove_foreign_key :marketplace_licenses, column: :proposed_company_id
    add_foreign_key :marketplace_licenses, :companies, column: :proposed_company_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :company_billing_state_changes, :companies
    add_foreign_key :company_billing_state_changes, :companies

    remove_foreign_key :marketplace_licenses, column: :proposed_company_id
    add_foreign_key :marketplace_licenses, :companies, column: :proposed_company_id
  end
end
