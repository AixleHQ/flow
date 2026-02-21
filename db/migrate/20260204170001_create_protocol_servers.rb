# frozen_string_literal: true

# Creates mcp_servers table for MCP (Model Context Protocol) server configurations
class CreateProtocolServers < ActiveRecord::Migration[8.0]
  def change
    create_table :mcp_servers do |t|
      t.string :name, null: false
      t.string :display_name, null: false
      t.string :url
      t.string :transport, default: "sse"
      t.jsonb :headers, default: {}
      t.text :description
      t.string :kind, null: false, default: "custom"
      t.references :scope, polymorphic: true, index: true
      t.boolean :enabled, default: true, null: false
      t.timestamps
    end

    add_index :mcp_servers, %i[name scope_type scope_id], unique: true
  end
end
