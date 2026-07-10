# frozen_string_literal: true

class CreateOauthCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_credentials do |t|
      t.references :owner, polymorphic: true, null: false   # User | Company | Project
      t.references :oauth_client, null: false, foreign_key: true
      t.references :mcp_server, foreign_key: true            # nullable; set for MCP-attached creds
      t.string   :provider, null: false                      # "sentry" | "railway" | "mcp:<host>"
      t.text     :encrypted_access_token
      t.text     :encrypted_refresh_token
      t.string   :token_type, default: "Bearer"
      t.string   :scopes
      t.datetime :expires_at                                 # PLAIN column — sweep queries it
      t.string   :status, null: false, default: "pending"    # pending|active|error|revoked
      t.string   :refresh_error
      t.datetime :last_refreshed_at
      t.jsonb    :metadata, null: false, default: {}         # account info from token response
      t.timestamps
    end

    add_index :oauth_credentials, %i[owner_type owner_id provider]
    add_index :oauth_credentials, %i[status expires_at]      # sweep scope (Phase 2)
    # One live credential per (owner, client, provider, mcp_server) — the upsert target.
    add_index :oauth_credentials,
              %i[owner_type owner_id oauth_client_id provider mcp_server_id],
              unique: true, name: "idx_oauth_credentials_unique_owner_client"
  end
end
