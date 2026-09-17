# frozen_string_literal: true

# One SCIM endpoint per company (CAP-6).
#
# The bearer token a customer's directory sends is stored as a digest, exactly
# like every other credential this app holds: it is a password by another name.
class CreateScimConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :scim_configurations do |t|
      t.references :company, null: false, foreign_key: true, index: { unique: true }
      t.string :token_digest, null: false
      t.boolean :enabled, null: false, default: true
      t.datetime :last_seen_at
      # Which provider row a SCIM-created membership is attributed to, so a
      # provisioned member is traceable to the connection that made them.
      t.references :identity_provider, foreign_key: true

      t.timestamps
    end

    add_index :scim_configurations, :token_digest, unique: true
  end
end
