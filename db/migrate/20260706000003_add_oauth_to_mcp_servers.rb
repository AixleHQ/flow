# frozen_string_literal: true

class AddOauthToMCPServers < ActiveRecord::Migration[8.1]
  def change
    add_column :mcp_servers, :auth_type,        :string, null: false, default: "none"
    add_column :mcp_servers, :credential_scope, :string, null: false, default: "shared"
  end
end
