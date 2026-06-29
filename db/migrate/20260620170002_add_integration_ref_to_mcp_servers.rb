# frozen_string_literal: true

class AddIntegrationRefToMCPServers < ActiveRecord::Migration[8.1]
  def change
    add_reference :mcp_servers, :integration,
                  null: true,
                  foreign_key: { on_delete: :cascade },
                  index: true
  end
end
