# frozen_string_literal: true

# An acceptance is evidence of an agreement, and the agreement may matter after
# the company or the person is gone. Deleting a company used to delete its
# acceptances with it, and deleting a person left a row that no longer said
# who accepted. Each row now carries who and for whom by name, and survives
# both deletions.
class KeepLegalAcceptancesAfterDeletion < ActiveRecord::Migration[8.1]
  def up
    add_column :legal_acceptances, :user_email, :string
    add_column :legal_acceptances, :company_name, :string
    add_column :legal_acceptances, :company_email_domain, :string

    remove_foreign_key :legal_acceptances, :companies
    add_foreign_key :legal_acceptances, :companies, on_delete: :nullify

    execute <<~SQL.squish
      UPDATE legal_acceptances SET user_email = users.email
      FROM users WHERE users.id = legal_acceptances.user_id
    SQL
    execute <<~SQL.squish
      UPDATE legal_acceptances SET company_name = companies.name, company_email_domain = companies.email_domain
      FROM companies WHERE companies.id = legal_acceptances.company_id
    SQL
  end

  def down
    remove_foreign_key :legal_acceptances, :companies
    add_foreign_key :legal_acceptances, :companies, on_delete: :cascade

    remove_column :legal_acceptances, :company_email_domain
    remove_column :legal_acceptances, :company_name
    remove_column :legal_acceptances, :user_email
  end
end
