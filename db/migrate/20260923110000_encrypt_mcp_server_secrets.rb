# frozen_string_literal: true

# MCP header and env values move into encrypted columns. The plaintext jsonb
# columns stay for the length of the rollout — the running code still reads them
# — and every write from the new code empties them. Once nothing runs the old
# code, `bin/rails maintenance:purge_plaintext_mcp_secrets` encrypts and clears what
# is left, and a later migration drops them.
#
# An OAuth credential for an MCP server records the resource it was issued for,
# so a server re-pointed somewhere else stops receiving it. Existing ones were
# issued for the URL the server has now.
#
# A credential also records who connected it — the person whose consent every
# holder of a shared credential now acts under.
#
# A config-item access records the channel that handed the value out: the
# get_config_item tool, or an MCP header/env reference.
class EncryptMCPServerSecrets < ActiveRecord::Migration[8.1]
  def up
    add_column :mcp_servers, :encrypted_headers, :text
    add_column :mcp_servers, :encrypted_env, :text
    add_column :oauth_credentials, :resource, :string
    add_reference :oauth_credentials, :connected_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :config_item_accesses, :channel, :string, null: false, default: "get_config_item"

    execute(<<~SQL.squish)
      UPDATE oauth_credentials SET resource = mcp_servers.url
        FROM mcp_servers
       WHERE oauth_credentials.mcp_server_id = mcp_servers.id AND oauth_credentials.resource IS NULL
    SQL
  end

  def down
    remove_column :config_item_accesses, :channel
    remove_reference :oauth_credentials, :connected_by, foreign_key: { to_table: :users }
    remove_column :oauth_credentials, :resource
    remove_column :mcp_servers, :encrypted_env
    remove_column :mcp_servers, :encrypted_headers
  end
end
