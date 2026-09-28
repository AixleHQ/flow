# frozen_string_literal: true

# Passkeys (CAP-4). The credential belongs to the USER and lives on their own
# device (AD-18): a company may decline to accept a passkey for entry, but never
# deletes one.
class CreateWebauthnCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :webauthn_credentials do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :external_id, null: false
      t.string :public_key, null: false
      t.bigint :sign_count, null: false, default: 0
      t.string :nickname
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :webauthn_credentials, :external_id, unique: true
  end
end
