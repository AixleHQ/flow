# frozen_string_literal: true

# Who signed the company up. Product analytics has no company-level person on
# its plan, so events no person caused (a Stripe webhook, a spent trial) are
# attributed to this one. Backfilled with each company's earliest admin, which
# is who the signup form makes the first member.
class AddCreatedByToCompanies < ActiveRecord::Migration[8.1]
  def up
    add_reference :companies, :created_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: true

    execute <<~SQL.squish
      UPDATE companies SET created_by_id = first_admin.user_id
      FROM (
        SELECT DISTINCT ON (company_id) company_id, user_id
        FROM company_memberships
        WHERE role = 'admin'
        ORDER BY company_id, created_at, id
      ) AS first_admin
      WHERE first_admin.company_id = companies.id
    SQL
  end

  def down
    remove_reference :companies, :created_by, foreign_key: { to_table: :users }, index: true
  end
end
