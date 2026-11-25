# frozen_string_literal: true

# AWS OIDC (docs/design/aws-oidc-integration.md §7): the instance's signing keys, the
# roles of a project's integration, the record of every STS exchange, and a role as one
# more kind of entry in a step's or a workflow's resource list.
class CreateAwsOidc < ActiveRecord::Migration[8.1]
  LINK_KINDS = %w[tool_id skill_id mcp_server_id asset_id repository_id config_item_id].freeze

  def up
    create_table :oidc_signing_keys do |t|
      t.string :kid, null: false, index: { unique: true }
      t.text :encrypted_private_key, null: false
      t.jsonb :public_jwk, null: false
      t.string :state, null: false
      t.datetime :activated_at
      t.datetime :retired_at
      t.timestamps
      t.check_constraint "state IN ('next', 'current', 'retired')", name: "oidc_signing_keys_state"
      t.index :state, unique: true, where: "state = 'current'", name: "index_oidc_signing_keys_one_current"
    end

    create_table :aws_oidc_roles do |t|
      t.references :integration, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :role_arn, null: false
      t.string :region, null: false
      t.integer :session_duration_seconds, null: false, default: 3600
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
      t.index %i[integration_id name], unique: true
      t.check_constraint "session_duration_seconds BETWEEN 900 AND 3600",
                         name: "aws_oidc_roles_session_duration"
    end

    create_table :aws_oidc_credential_issuances do |t|
      t.references :aws_oidc_role, foreign_key: { on_delete: :nullify }
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :terminal_session, foreign_key: { on_delete: :cascade }
      t.references :step_run, foreign_key: { on_delete: :nullify }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :role_name, null: false
      t.string :role_arn, null: false
      t.string :subject, null: false
      t.string :jti, null: false
      t.string :access_key_id, null: false
      t.text :encrypted_secrets, null: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
      t.index %i[project_id created_at], name: "index_aws_oidc_issuances_on_project_and_created_at"
    end

    %i[step_resource_links workflow_resource_links].each do |table|
      add_reference table, :aws_oidc_role, foreign_key: { on_delete: :cascade }, index: false
      owner = table == :step_resource_links ? :step_id : :workflow_id
      add_index table, [ owner, :aws_oidc_role_id ], unique: true, where: "aws_oidc_role_id IS NOT NULL"
      add_index table, :aws_oidc_role_id, where: "aws_oidc_role_id IS NOT NULL"
      replace_one_resource_check(table, LINK_KINDS + %w[aws_oidc_role_id])
    end
  end

  def down
    %i[step_resource_links workflow_resource_links].each do |table|
      execute "DELETE FROM #{table} WHERE aws_oidc_role_id IS NOT NULL"
      replace_one_resource_check(table, LINK_KINDS)
      remove_reference table, :aws_oidc_role, foreign_key: true, index: false
    end
    drop_table :aws_oidc_credential_issuances
    drop_table :aws_oidc_roles
    drop_table :oidc_signing_keys
  end

  private

  def replace_one_resource_check(table, columns)
    remove_check_constraint table, name: "#{table}_one_resource"
    add_check_constraint table, "num_nonnulls(#{columns.join(', ')}) = 1", name: "#{table}_one_resource"
  end
end
