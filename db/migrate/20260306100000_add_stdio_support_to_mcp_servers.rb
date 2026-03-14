# frozen_string_literal: true

class AddStdioSupportToMCPServers < ActiveRecord::Migration[7.2]
  def change
    add_column :mcp_servers, :command, :string
  end
end
