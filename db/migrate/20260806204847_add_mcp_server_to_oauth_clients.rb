# frozen_string_literal: true

# A manual OAuth client: credentials an operator registered by hand at the provider,
# for an authorization server that will not let us register ourselves (Vercel's DCR
# approves loopback callbacks only; Atlassian publishes no usable metadata).
#
# It is scoped to ONE MCP server rather than shared by issuer the way a dcr/cimd
# client is, and that is a tenancy rule, not a preference: a dcr client is ours, but
# a manual client's credentials belong to whoever pasted them, and their users must
# not end up authorizing into another tenant's OAuth app.
class AddMCPServerToOauthClients < ActiveRecord::Migration[8.1]
  def change
    add_reference :oauth_clients, :mcp_server, foreign_key: true, index: false

    # One manual client per server. Rows with no server (dcr/cimd/static) are exempt.
    add_index :oauth_clients, :mcp_server_id, unique: true, where: "mcp_server_id IS NOT NULL"

    # (issuer, client_id) stays unique for the shared clients, and stops applying to
    # server-scoped ones: two projects may legitimately paste the same OAuth app.
    remove_index :oauth_clients, column: %i[issuer client_id], unique: true,
                                 name: "index_oauth_clients_on_issuer_and_client_id"
    add_index :oauth_clients, %i[issuer client_id], unique: true,
              where: "mcp_server_id IS NULL", name: "index_oauth_clients_on_issuer_and_client_id"

    # A manual client is created from a form, BEFORE discovery has run and can say
    # what the endpoints are — the operator only has a client id and secret. The
    # model still requires all three for every other source; this only removes the
    # database's ability to represent the intermediate state.
    change_column_null :oauth_clients, :issuer, true
    change_column_null :oauth_clients, :authorization_endpoint, true
    change_column_null :oauth_clients, :token_endpoint, true
  end
end
