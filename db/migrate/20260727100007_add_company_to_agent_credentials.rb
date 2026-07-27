# frozen_string_literal: true

# Agent credentials become per-COMPANY, not per-user: a consultant working for
# two companies must authenticate a separate agent account for each, so vendor
# spend is billed to the company that incurred it instead of pooling on one
# token.
#
# Backfill is unambiguous: memberships were themselves backfilled from
# users.company_id, so every pre-existing user has exactly one active
# membership, and each credential maps 1:1 onto that company.
class AddCompanyToAgentCredentials < ActiveRecord::Migration[8.1]
  def up
    add_column :agent_credentials, :company_id, :bigint
    add_index :agent_credentials, :company_id

    execute <<~SQL
      UPDATE agent_credentials ac
      SET company_id = cm.company_id
      FROM (
        SELECT DISTINCT ON (user_id) user_id, company_id
        FROM company_memberships
        ORDER BY user_id, (state = 'active') DESC, accepted_at ASC NULLS LAST, id ASC
      ) cm
      WHERE cm.user_id = ac.user_id
    SQL

    # A credential whose owner has no membership at all (super admin, or a user
    # whose memberships were revoked) has no company to belong to and no longer
    # means anything.
    execute "DELETE FROM agent_credentials WHERE company_id IS NULL"

    change_column_null :agent_credentials, :company_id, false
    add_foreign_key :agent_credentials, :companies

    remove_index :agent_credentials, name: "index_agent_credentials_on_user_id_and_agent_type"
    add_index :agent_credentials, %i[user_id company_id agent_type],
              unique: true, name: "index_agent_credentials_on_user_company_agent"
  end

  def down
    remove_index :agent_credentials, name: "index_agent_credentials_on_user_company_agent"
    # De-duplicate before the narrower unique index can go back on: keep the
    # most recently used credential per (user, agent_type).
    execute <<~SQL
      DELETE FROM agent_credentials
      WHERE id NOT IN (
        SELECT DISTINCT ON (user_id, agent_type) id
        FROM agent_credentials
        ORDER BY user_id, agent_type, last_used_at DESC NULLS LAST, id DESC
      )
    SQL
    add_index :agent_credentials, %i[user_id agent_type],
              unique: true, name: "index_agent_credentials_on_user_id_and_agent_type"

    remove_foreign_key :agent_credentials, :companies
    remove_index :agent_credentials, :company_id
    remove_column :agent_credentials, :company_id
  end
end
