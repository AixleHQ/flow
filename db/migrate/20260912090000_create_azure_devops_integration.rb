# frozen_string_literal: true

# Azure DevOps integration, core release (docs/design/azure-devops-integration.md).
#
# Three additive pieces, none of which touch an existing provider's rows:
#
# 1. `azure_devops_installations` — the approved company→organization binding.
#    It is NOT an Integration: a company-wide Integration would expose tools and
#    repositories to every project, and this record exists precisely to say
#    "this Aixle company may reach this Azure organization", separately from
#    "this project has connected one of its Azure projects".
# 2. `integrations.azure_devops_installation_id` — the project connection's
#    pointer at that binding. Null in PAT mode, required in service-principal
#    mode (model-level, since one column cannot express "required for one
#    provider in one auth mode").
# 3. Azure identity columns on `repositories` plus the operations ledger that
#    makes agent mutations replay-safe.
class CreateAzureDevopsIntegration < ActiveRecord::Migration[8.1]
  def change
    create_table :azure_devops_installations do |t|
      t.references :company, null: false, foreign_key: true
      # Operator who verified the customer administrator's authority. Nullable
      # only so a deployment-level seed can exist; the service always sets it.
      t.bigint :approved_by_id
      t.datetime :approved_at

      # Azure identity. tenant_id and organization_slug are the two values a
      # human can supply; organization_id and service_principal_object_id are
      # filled in from verified provider data and are immutable afterwards.
      t.string :tenant_id, null: false
      t.string :client_id, null: false
      t.string :organization_slug, null: false
      t.string :organization_id
      t.string :service_principal_object_id

      # Approved scope. An empty array means NO projects — never "all".
      t.jsonb :allowed_project_ids, null: false, default: []

      # Resolves to trusted operator settings only (Settings.azure_devops.apps.*).
      # A user cannot submit an arbitrary credential reference.
      t.string :app_config_key, null: false, default: "default"

      # App-only access token cache. Encrypted at rest through Encryptable, with
      # the credential generation and resource recorded so a rotation or a scope
      # change can never be served from a stale entry.
      t.text :encrypted_access_token
      t.datetime :token_expires_at
      t.string :token_credential_generation
      t.string :token_resource

      t.string :status, null: false, default: "inactive"
      t.string :error_code
      t.datetime :last_verified_at
      t.timestamps
    end

    # The design names (company, organization_id, tenant, principal) as the key.
    # Three of those four are null until the first verification, and Postgres
    # treats NULLs as distinct — such an index would permit unlimited duplicate
    # pending rows. The slug is the one organization identifier present from the
    # start and is globally unique in Azure DevOps, so it carries the constraint.
    add_index :azure_devops_installations,
              %i[company_id tenant_id organization_slug],
              unique: true,
              name: "idx_ado_installations_identity"
    add_index :azure_devops_installations, :token_expires_at,
              name: "idx_ado_installations_token_expiry"
    add_foreign_key :azure_devops_installations, :users, column: :approved_by_id

    # restrict_with_exception, not cascade: deleting an installation that still
    # has project integrations attached would silently strip their credentials.
    # Disable it first, then detach deliberately.
    add_reference :integrations, :azure_devops_installation,
                  null: true,
                  foreign_key: { to_table: :azure_devops_installations, on_delete: :restrict }

    add_column :repositories, :external_id, :string
    add_column :repositories, :external_project_id, :string
    add_column :repositories, :external_organization_id, :string

    # Source identity for provider-backed rows that have one. Partial, so the
    # millions of GitHub/GitLab rows with three NULLs do not collide.
    add_index :repositories,
              %i[scope_type scope_id external_organization_id external_project_id external_id],
              unique: true,
              where: "external_id IS NOT NULL",
              name: "idx_repositories_external_identity"

    # Mutation ledger. Azure supplies no exactly-once guarantee, so an agent
    # retry is made safe here instead: one row per (integration, operation_key),
    # carrying the request digest so the same key with a different payload is a
    # conflict rather than a silent replay of the wrong thing.
    create_table :azure_devops_operations do |t|
      t.references :integration, null: false, foreign_key: true
      t.bigint :terminal_session_id
      t.bigint :user_id
      t.string :operation_key, null: false
      t.string :operation, null: false
      t.string :request_digest, null: false
      t.string :state, null: false, default: "pending"
      t.string :target_kind
      t.string :target_id
      t.jsonb :result, null: false, default: {}
      t.string :error_code
      t.timestamps
    end
    add_index :azure_devops_operations, %i[integration_id operation_key],
              unique: true, name: "idx_ado_operations_key"
    add_index :azure_devops_operations, :created_at, name: "idx_ado_operations_created_at"
  end
end
