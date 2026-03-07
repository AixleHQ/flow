# frozen_string_literal: true

class AddEnvToMCPServers < ActiveRecord::Migration[7.2]
  def change
    add_column :mcp_servers, :env, :jsonb, default: {}
  end
end
