# frozen_string_literal: true

# Full cutover to CompanyMembership: company/role/invitation data now lives on
# the membership. The global unique email index is kept untouched.
class RemoveCompanyFieldsFromUsers < ActiveRecord::Migration[8.1]
  def up
    remove_index :users, name: "index_users_on_company_id_and_email"
    remove_index :users, name: "index_users_on_company_id"
    remove_index :users, name: "index_users_on_invited_by_id"
    remove_index :users, name: "index_users_on_role"

    remove_foreign_key :users, :companies
    remove_foreign_key :users, column: :invited_by_id

    remove_column :users, :company_id
    remove_column :users, :role
    remove_column :users, :invited_by_id
    remove_column :users, :invited_at
  end

  def down
    add_column :users, :company_id, :bigint
    add_column :users, :role, :string
    add_column :users, :invited_by_id, :bigint
    add_column :users, :invited_at, :datetime

    # Best-effort data restore from company_memberships (oldest membership per
    # user wins) before the indexes/FKs go back on.
    if table_exists?(:company_memberships)
      execute <<~SQL
        UPDATE users u
        SET company_id = cm.company_id,
            role = cm.role,
            invited_by_id = cm.invited_by_id,
            invited_at = cm.invited_at
        FROM (
          SELECT DISTINCT ON (user_id) user_id, company_id, role, invited_by_id, invited_at
          FROM company_memberships
          ORDER BY user_id, created_at ASC, id ASC
        ) cm
        WHERE cm.user_id = u.id
      SQL
    end
    execute "UPDATE users SET role = 'super_admin' WHERE super_admin = true"

    add_foreign_key :users, :companies
    add_foreign_key :users, :users, column: :invited_by_id

    add_index :users, %i[company_id email], name: "index_users_on_company_id_and_email",
                                            unique: true, where: "(company_id IS NOT NULL)"
    add_index :users, :company_id
    add_index :users, :invited_by_id
    add_index :users, :role
  end
end
