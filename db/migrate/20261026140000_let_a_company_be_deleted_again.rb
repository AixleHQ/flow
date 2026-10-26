# frozen_string_literal: true

class LetACompanyBeDeletedAgain < ActiveRecord::Migration[8.1]
  # Two foreign keys added on this branch refuse `DELETE FROM companies`, which
  # is what the admin's delete button runs.
  #
  # `company_billing_state_changes` holds a row for every company whose billing
  # state has changed once, so in practice it refuses all of them. Its twin
  # `company_capacity_changes` cascades, and the log is worth exactly as much as
  # the company it describes -- so it cascades too.
  #
  # `marketplace_licenses.proposed_company_id` names a company a subscription
  # was offered to. That company going away does not invalidate the licence; it
  # only means nobody is being asked any more, which is what nullify says. The
  # licence's own `company_id` is already nullified, by the association rather
  # than by the database.
  #
  # A separate migration rather than an edit of the two that added them: both
  # have run on staging, and a change in place would be applied nowhere.
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
