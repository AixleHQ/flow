# frozen_string_literal: true

class AddFederationToAzureDevops < ActiveRecord::Migration[8.1]
  def change
    # The subject a customer's federated credential trusts is built from this, so
    # it must never change and must not be derived from anything a user can edit
    # (a company's name and slug both can be). The default also backfills every
    # existing row with its own value.
    add_column :companies, :public_id, :uuid, default: -> { "gen_random_uuid()" }, null: false
    add_index :companies, :public_id, unique: true

    # shared_app: Aixle's multi-tenant Entra app. federated: the customer's own
    # app, trusting this deployment as an OIDC issuer.
    add_column :azure_devops_installations, :credential_kind, :string, default: "shared_app", null: false
    # A federated installation uses no operator app configuration.
    change_column_null :azure_devops_installations, :app_config_key, true
  end
end
