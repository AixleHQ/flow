# frozen_string_literal: true

# Personal MCP: one opt-in token per user granting their own access level
# over the global (session-less) MCP server. Only the SHA256 digest is
# stored; the plaintext (amcp_-prefixed) is shown once at generation.
class AddMCPTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :mcp_token_digest, :string
    add_column :users, :mcp_token_last_used_at, :datetime
    add_index :users, :mcp_token_digest, unique: true
  end
end
