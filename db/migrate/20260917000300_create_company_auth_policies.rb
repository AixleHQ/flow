# frozen_string_literal: true

# The only thing a company admin toggles (AD-4). The effective set for a company
# is `deployment allowlist ∩ enabled policies`, computed only by
# Auth::PolicyResolver.
class CreateCompanyAuthPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :company_auth_policies do |t|
      t.references :company, null: false, foreign_key: true, index: true
      t.references :identity_provider, null: false, foreign_key: true, index: true
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :company_auth_policies, %i[company_id identity_provider_id], unique: true,
              name: "index_company_auth_policies_unique_pair"
  end
end
