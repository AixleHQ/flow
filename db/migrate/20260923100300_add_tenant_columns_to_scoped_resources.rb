# frozen_string_literal: true

# Real tenant columns next to the polymorphic scope pair, so the database can hold
# what `scope_type/scope_id` cannot:
#
# - foreign keys: a project or company can no longer be deleted out from under its
#   rows, and no row can point at one that is gone;
# - a composite key tying each row's company to its project's company, and the
#   repository → integration reference to one company;
# - a check that the new columns say exactly what the scope pair says.
#
# The scope pair stays: it is what the application reads and writes, and the
# TenantColumns concern keeps these in step with it.
#
# Constraints are added NOT VALID. They hold for every row written from now on;
# rows that are already inconsistent — orphans left by an earlier delete — are
# listed by the operator runbook and validated once cleaned up.
#
# For one release the check also passes a row that carries neither column: pods of
# the previous release — mid-rollout, or after a rollback — insert rows without
# them. The follow-up backfills those rows and swaps in the strict rule.
class AddTenantColumnsToScopedResources < ActiveRecord::Migration[8.1]
  PROJECT = "scope_type = 'Project' AND project_id = scope_id AND company_id IS NOT NULL"
  COMPANY = "scope_type = 'Company' AND project_id IS NULL AND company_id = scope_id"
  COMPANY_SCOPED = %i[assets folders session_concurrency_limits].freeze

  RULES = {
    agents: PROJECT,
    config_items: PROJECT,
    repositories: PROJECT,
    skills: PROJECT,
    session_concurrency_limits: "(#{PROJECT}) OR (#{COMPANY})",
    # Platform rows (code tools, internal MCP servers) belong to no tenant.
    tools: "(scope_type IS NULL AND scope_id IS NULL AND project_id IS NULL AND company_id IS NULL) OR (#{PROJECT})",
    mcp_servers: "(scope_type IS NULL AND scope_id IS NULL AND project_id IS NULL AND company_id IS NULL) OR (#{PROJECT})",
    workflows: "(scope_type = 'System' AND project_id IS NULL AND company_id IS NULL) OR (#{PROJECT})",
    assets: "(#{PROJECT}) OR (#{COMPANY})",
    folders: "(#{PROJECT}) OR (#{COMPANY})"
  }.freeze

  def up
    add_index :projects, %i[id company_id], unique: true
    add_index :integrations, %i[id company_id], unique: true

    # A limit whose project or company no longer exists still reserved capacity.
    execute(<<~SQL.squish)
      DELETE FROM session_concurrency_limits
       WHERE (scope_type = 'Project' AND NOT EXISTS (SELECT 1 FROM projects WHERE projects.id = session_concurrency_limits.scope_id))
          OR (scope_type = 'Company' AND NOT EXISTS (SELECT 1 FROM companies WHERE companies.id = session_concurrency_limits.scope_id))
    SQL

    RULES.each do |table, rule|
      add_column table, :project_id, :bigint
      add_column table, :company_id, :bigint

      execute(<<~SQL.squish)
        UPDATE #{table} SET project_id = projects.id, company_id = projects.company_id
          FROM projects
         WHERE #{table}.scope_type = 'Project' AND projects.id = #{table}.scope_id
      SQL
      if table.in?(COMPANY_SCOPED)
        execute("UPDATE #{table} SET company_id = scope_id WHERE scope_type = 'Company'")
      end

      add_index table, :project_id
      add_index table, :company_id
      add_foreign_key table, :projects, on_delete: :cascade, validate: false
      add_foreign_key table, :companies, on_delete: :cascade, validate: false
      add_foreign_key table, :projects, column: %i[project_id company_id], primary_key: %i[id company_id],
                                        on_delete: :cascade, validate: false,
                                        name: "fk_#{table}_project_company"
      add_check_constraint table, "(project_id IS NULL AND company_id IS NULL) OR (#{rule})",
                           name: "#{table}_tenant_columns", validate: false
    end

    # A repository's integration must belong to the repository's company.
    add_foreign_key :repositories, :integrations, column: %i[integration_id company_id], primary_key: %i[id company_id],
                                                  validate: false, name: "fk_repositories_integration_company"
  end

  def down
    remove_foreign_key :repositories, name: "fk_repositories_integration_company"
    RULES.each_key do |table|
      remove_check_constraint table, name: "#{table}_tenant_columns"
      remove_foreign_key table, name: "fk_#{table}_project_company"
      remove_foreign_key table, :companies
      remove_foreign_key table, :projects
      remove_column table, :company_id
      remove_column table, :project_id
    end
    remove_index :integrations, %i[id company_id]
    remove_index :projects, %i[id company_id]
  end
end
