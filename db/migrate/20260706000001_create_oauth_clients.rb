# frozen_string_literal: true

class CreateOauthClients < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_clients do |t|
      t.string  :issuer, null: false                  # authorization server identity
      t.string  :authorization_endpoint, null: false
      t.string  :token_endpoint, null: false
      t.string  :registration_endpoint                # present only when DCR used (Phase 3)
      t.string  :client_id, null: false
      t.text    :encrypted_client_secret              # Encryptable; null for public/PKCE-only clients
      t.string  :scopes
      t.string  :source, null: false                  # "static" (Settings-backed) | "dcr" (Phase 3)
      t.jsonb   :metadata, null: false, default: {}   # raw RFC 8414 / 7591 responses
      t.timestamps
    end

    # A static provider is uniquely identified by (issuer, client_id); reconcile against it.
    add_index :oauth_clients, %i[issuer client_id], unique: true
    add_index :oauth_clients, :source
  end
end
