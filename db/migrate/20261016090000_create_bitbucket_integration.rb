# frozen_string_literal: true

# Bitbucket Cloud integration and the provider-neutral pull-request ledger
# (docs/design/bitbucket-integration.md §6).
class CreateBitbucketIntegration < ActiveRecord::Migration[8.1]
  def change
    create_table :bitbucket_installations do |t|
      t.string :forge_installation_id, null: false
      t.string :forge_environment_id, null: false
      t.string :workspace_uuid, null: false
      t.string :workspace_slug
      t.string :workspace_name
      # Null while unbound: an installation proves only that the app reaches a
      # workspace, never which Aixle company owns it (§5.5).
      t.bigint :company_id
      t.bigint :bound_by_id
      t.datetime :bound_at
      t.string :installer_account_id
      t.string :status, null: false, default: "active"
      t.string :error_code
      t.text :encrypted_access_token
      t.datetime :token_expires_at
      t.datetime :last_invocation_at
      t.string :app_version
      t.timestamps
    end
    add_index :bitbucket_installations, :forge_installation_id, unique: true
    add_index :bitbucket_installations, %i[forge_environment_id workspace_uuid], unique: true,
                                        where: "status <> 'uninstalled'", name: "idx_bitbucket_installations_live_workspace"
    add_index :bitbucket_installations, :company_id
    add_index :bitbucket_installations, :token_expires_at
    add_foreign_key :bitbucket_installations, :companies, on_delete: :nullify
    add_foreign_key :bitbucket_installations, :users, column: :bound_by_id, on_delete: :nullify

    create_table :bitbucket_pairings do |t|
      t.bigint :bitbucket_installation_id, null: false
      t.string :public_id, null: false
      t.string :secret_digest, null: false
      t.string :account_id, null: false
      t.string :workspace_uuid, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.bigint :consumed_by_id
      t.bigint :project_id
      t.timestamps
    end
    add_index :bitbucket_pairings, :public_id, unique: true
    add_index :bitbucket_pairings, :bitbucket_installation_id
    add_foreign_key :bitbucket_pairings, :bitbucket_installations, on_delete: :cascade
    add_foreign_key :bitbucket_pairings, :projects, on_delete: :nullify
    add_foreign_key :bitbucket_pairings, :users, column: :consumed_by_id, on_delete: :nullify

    add_reference :integrations, :bitbucket_installation, foreign_key: { on_delete: :restrict }

    create_table :pull_request_operations do |t|
      t.bigint :integration_id, null: false
      t.bigint :repository_id, null: false
      t.string :operation, null: false
      t.string :operation_key, null: false
      t.string :request_digest, null: false
      t.string :state, null: false, default: "pending"
      t.jsonb :result, null: false, default: {}
      t.string :error_code
      t.string :pull_request_number
      t.bigint :terminal_session_id
      t.bigint :workflow_run_id
      t.bigint :workflow_id
      t.bigint :user_id
      t.timestamps
    end
    add_index :pull_request_operations, %i[integration_id operation_key], unique: true,
                                        name: "idx_pull_request_operations_key"
    add_index :pull_request_operations, %i[repository_id pull_request_number]
    add_foreign_key :pull_request_operations, :integrations, on_delete: :cascade
    add_foreign_key :pull_request_operations, :repositories, on_delete: :cascade
  end
end
