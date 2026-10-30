# frozen_string_literal: true

# One row per AWS Marketplace agreement for the SaaS listing.
#
# Keyed on the licence rather than the customer because a product on Concurrent
# Agreements — which every SaaS product created after 1 June 2026 is — lets one
# AWS account hold several live agreements at once, and stops populating
# CustomerIdentifier altogether.
class CreateMarketplaceLicenses < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_licenses do |t|
      t.string :license_arn, null: false
      t.string :customer_aws_account_id, null: false
      t.string :product_code, null: false
      t.string :agreement_id
      # Not populated under Concurrent Agreements. Stored when AWS sends one so
      # that a question about an older integration has an answer; nothing keys
      # on it.
      t.string :customer_identifier

      # Null until somebody finishes registering. A subscription can arrive
      # before anyone has an account, and that state has to be visible rather
      # than impossible.
      t.references :company, foreign_key: true, index: false

      t.string :subscription_state, null: false, default: "pending"
      t.string :offer_identifier
      # The x-amzn-marketplace-offer-type parameter exactly as it arrived on the
      # registration POST, or null. A string rather than a boolean because what a
      # free trial means for us is not settled, and a boolean would bake in an
      # answer we do not have.
      t.string :registered_offer_type

      t.datetime :subscribed_at
      t.datetime :ended_at

      t.timestamps
    end

    # The licence is the identity: a second arrival carrying one we already hold
    # is the same purchase, and must land on the company it already made.
    add_index :marketplace_licenses, :license_arn, unique: true
    # One company holds at most one licence, which is what stops a second
    # subscription attaching itself to a workspace that is already paid for.
    add_index :marketplace_licenses, :company_id, unique: true, where: "company_id IS NOT NULL"
    # Deliberately not unique: several agreements per AWS account is the feature
    # Concurrent Agreements exists to provide.
    add_index :marketplace_licenses, :customer_aws_account_id
    add_index :marketplace_licenses, :subscription_state
  end
end
