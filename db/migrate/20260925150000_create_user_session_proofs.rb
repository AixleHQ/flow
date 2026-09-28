# frozen_string_literal: true

# Proofs APPEND (AD-6): a session records every method it has satisfied, and a
# company is satisfied when the intersection with its currently-enabled
# providers is non-empty. That is what stops step-up ping-pong for a user who
# belongs to two companies with disjoint policies.
class CreateUserSessionProofs < ActiveRecord::Migration[8.1]
  def change
    create_table :user_session_proofs do |t|
      t.references :user_session, null: false, foreign_key: true, index: true
      t.references :identity_provider, null: false, foreign_key: true, index: true
      t.datetime :proved_at, null: false

      t.timestamps
    end

    add_index :user_session_proofs, %i[user_session_id identity_provider_id], unique: true,
              name: "index_user_session_proofs_unique_pair"
  end
end
