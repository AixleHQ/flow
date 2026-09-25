# frozen_string_literal: true

# The schema-level loose ends, in one place.
#
# - Integer columns that hold bigint primary keys (workflows.scope_id is a
#   project id; the audit trail's auditable/associated/user ids).
# - Foreign keys that were never declared. Orphans are cleared first and each
#   key is validated separately, so the lock that adds it is brief.
# - Unique indexes whose nullable column meant "not scoped" or "no MCP server":
#   Postgres treats NULLs as distinct, so two rows with the same name and no
#   scope, or two provider credentials for one owner, both passed. They are
#   rebuilt NULLS NOT DISTINCT (Postgres 15+) — unless existing rows already
#   collide, which is reported and left for an operator rather than failing
#   the deploy.
class SchemaHygiene < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  NULLS_NOT_DISTINCT = [
    [ :mcp_servers, "index_mcp_servers_on_name_and_scope_type_and_scope_id", %w[name scope_type scope_id] ],
    [ :skills, "index_skills_on_scope_type_and_scope_id_and_name", %w[scope_type scope_id name] ],
    [ :oauth_credentials, "idx_oauth_credentials_unique_owner_client",
      %w[owner_type owner_id oauth_client_id provider mcp_server_id] ],
    [ :azure_devops_subscriptions, "idx_ado_subscriptions_integration_project_event",
      %w[integration_id azure_project_id event_type] ]
  ].freeze

  def up
    change_column :workflows, :scope_id, :bigint, null: false
    change_column :audits, :auditable_id, :bigint
    change_column :audits, :associated_id, :bigint
    change_column :audits, :user_id, :bigint

    execute <<~SQL.squish
      UPDATE assets SET step_run_id = NULL
      WHERE step_run_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM step_runs WHERE step_runs.id = assets.step_run_id)
    SQL
    add_foreign_key :assets, :step_runs, on_delete: :nullify, validate: false, if_not_exists: true
    validate_foreign_key :assets, :step_runs

    execute <<~SQL.squish
      UPDATE trigger_events SET company_id = NULL
      WHERE company_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM companies WHERE companies.id = trigger_events.company_id)
    SQL
    add_foreign_key :trigger_events, :companies, on_delete: :cascade, validate: false, if_not_exists: true
    validate_foreign_key :trigger_events, :companies

    execute <<~SQL.squish
      UPDATE users SET last_company_id = NULL
      WHERE last_company_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM companies WHERE companies.id = users.last_company_id)
    SQL
    add_foreign_key :users, :companies, column: :last_company_id, on_delete: :nullify, validate: false, if_not_exists: true
    validate_foreign_key :users, :companies, column: :last_company_id

    NULLS_NOT_DISTINCT.each { |table, name, columns| rebuild_nulls_not_distinct(table, name, columns) }
  end

  def down
    NULLS_NOT_DISTINCT.each do |table, name, columns|
      remove_index table, name: name, algorithm: :concurrently, if_exists: true
      add_index table, columns, unique: true, name: name, algorithm: :concurrently
    end
    remove_foreign_key :users, column: :last_company_id, if_exists: true
    remove_foreign_key :trigger_events, :companies, if_exists: true
    remove_foreign_key :assets, :step_runs, if_exists: true
  end

  private

  def rebuild_nulls_not_distinct(table, name, columns)
    list = columns.map { |c| connection.quote_column_name(c) }.join(", ")
    duplicates = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM (SELECT 1 FROM #{connection.quote_table_name(table)} GROUP BY #{list} HAVING COUNT(*) > 1) d
    SQL
    if duplicates.positive?
      say "#{table}: #{duplicates} group(s) of rows already share (#{columns.join(', ')}); #{name} left as it was"
      return
    end

    # Built beside the old one and swapped in, so uniqueness is never off.
    replacement = "#{name}_nnd"
    add_index table, columns, unique: true, name: replacement, nulls_not_distinct: true, algorithm: :concurrently
    remove_index table, name: name, algorithm: :concurrently, if_exists: true
    rename_index table, replacement, name
  end
end
