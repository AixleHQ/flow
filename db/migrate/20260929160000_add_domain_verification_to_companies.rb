# frozen_string_literal: true

class AddDomainVerificationToCompanies < ActiveRecord::Migration[8.1]
  def up
    # Claiming a domain at signup proves one mailbox at it and nothing more.
    # Proving the domain is a DNS record only its owner can publish, and it is
    # what turns "everyone from this domain joins here" from a claim into a fact.
    add_column :companies, :domain_verification_token, :string
    add_column :companies, :domain_verified_at, :datetime

    # Every company that already exists predates the rule: ours, every
    # self-hosted installation's, and anything an operator made from the admin.
    # Leaving them unverified would switch off domain auto-join for all of them.
    execute("UPDATE companies SET domain_verified_at = created_at")
  end

  def down
    remove_column :companies, :domain_verification_token
    remove_column :companies, :domain_verified_at
  end
end
