# frozen_string_literal: true

# What can authenticate someone (AD-4). Deliberately NOT "a row per method per
# company": password and Google are one deployment-wide thing each, so forcing
# them into a per-company row would mean one identity per company for a user
# with one password, and would force company-first login.
class CreateIdentityProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :identity_providers do |t|
      t.string :kind, null: false
      t.string :scope, null: false
      t.references :company, foreign_key: true, index: true
      t.string :name
      t.jsonb :config, null: false, default: {}
      t.text :encrypted_secret

      t.timestamps
    end

    # A deployment-scoped provider is a singleton per kind: there is one
    # password provider, one Google provider, one passkey provider.
    add_index :identity_providers, :kind, unique: true,
              where: "scope = 'deployment'", name: "index_identity_providers_unique_deployment_kind"
    add_index :identity_providers, %i[company_id kind name], unique: true,
              where: "scope = 'company'", name: "index_identity_providers_unique_company_connection"

    add_check_constraint :identity_providers,
                         "(scope = 'deployment' AND company_id IS NULL) OR (scope = 'company' AND company_id IS NOT NULL)",
                         name: "identity_providers_scope_company_consistency"
  end
end
