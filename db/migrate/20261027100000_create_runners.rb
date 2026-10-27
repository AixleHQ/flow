# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §2.1. Runners carry company_id and a
# nullable project_id directly, like integrations, so tenant integrity comes from
# the composite keys of AddTenantColumnsToScopedResources rather than TenantColumns.
class CreateRunners < ActiveRecord::Migration[8.1]
  def change
    create_table :runners do |t|
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.references :project, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :runner_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :status_reason
      t.references :integration, foreign_key: true
      t.jsonb :config, null: false, default: {}
      t.integer :max_concurrency, null: false
      t.integer :max_environments
      t.string :reuse_policy, null: false
      t.jsonb :capabilities, null: false, default: {}
      t.jsonb :health, null: false, default: {}
      t.datetime :last_seen_at
      # Nullable like every other authorship column (EnablePermanentUserDeletion):
      # a permanently deleted user must not take the company's runners with them.
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :disabled_at
      t.datetime :revoked_at
      t.datetime :deleted_at
      t.timestamps

      t.index "company_id, COALESCE(project_id, 0::bigint), lower((name)::text)",
              unique: true, where: "deleted_at IS NULL", name: "index_runners_on_scope_and_name"
      t.check_constraint "max_concurrency > 0", name: "runners_max_concurrency_positive"
      t.check_constraint "(runner_type = 'coder') = (integration_id IS NOT NULL)", name: "runners_coder_integration"
      t.check_constraint "runner_type <> 'manual' OR max_environments IS NULL", name: "runners_manual_no_pool_size"
      t.check_constraint "max_environments IS NULL OR max_environments > 0", name: "runners_max_environments_positive"
    end

    add_foreign_key :runners, :projects, column: %i[project_id company_id], primary_key: %i[id company_id],
                                         on_delete: :cascade, name: "fk_runners_project_company"
    add_foreign_key :runners, :integrations, column: %i[integration_id company_id], primary_key: %i[id company_id],
                                             name: "fk_runners_integration_company"
  end
end
