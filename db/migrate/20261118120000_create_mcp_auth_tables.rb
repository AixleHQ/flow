# frozen_string_literal: true

# Aixle as the OAuth 2.1 authorization server of its own personal MCP server
# (docs/design/mcp-oauth-server.md): clients that registered themselves (DCR),
# the grants people give them, and the tokens those grants carry.
class CreateMCPAuthTables < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_auth_clients do |t|
      t.string :client_id, null: false
      t.string :client_name
      t.string :redirect_uris, array: true, null: false, default: []
      t.datetime :last_used_at
      t.timestamps

      t.index :client_id, unique: true
    end

    create_table :mcp_auth_grants do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :client_id, null: false
      t.string :client_kind, null: false
      t.string :client_name, null: false
      t.string :redirect_uri, null: false
      t.string :resource
      t.string :scope
      t.bigint :proof_provider_ids, array: true, null: false, default: []
      t.string :code_digest
      t.string :code_challenge
      t.datetime :code_expires_at
      t.datetime :code_used_at
      t.datetime :expires_at
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps

      t.index :code_digest, unique: true
      t.index %i[user_id revoked_at]
    end

    create_table :mcp_auth_tokens do |t|
      t.references :grant, null: false, foreign_key: { to_table: :mcp_auth_grants, on_delete: :cascade }
      t.string :kind, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :rotated_at
      t.datetime :created_at, null: false

      t.index :token_digest, unique: true
    end
  end
end
