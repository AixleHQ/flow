# frozen_string_literal: true

class CreateSessionConfigJoinTables < ActiveRecord::Migration[8.1]
  def change
    create_table :session_tools, id: false do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :tool, null: false, foreign_key: { on_delete: :cascade }, index: false
    end
    add_index :session_tools, [ :terminal_session_id, :tool_id ], unique: true

    create_table :session_skills, id: false do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :skill, null: false, foreign_key: { on_delete: :cascade }, index: false
    end
    add_index :session_skills, [ :terminal_session_id, :skill_id ], unique: true

    create_table :session_mcp_servers, id: false do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :mcp_server, null: false, foreign_key: { to_table: :mcp_servers, on_delete: :cascade }, index: false
    end
    add_index :session_mcp_servers, [ :terminal_session_id, :mcp_server_id ], unique: true

    create_table :session_input_assets, id: false do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :asset, null: false, foreign_key: { on_delete: :cascade }, index: false
    end
    add_index :session_input_assets, [ :terminal_session_id, :asset_id ], unique: true

    create_table :session_repositories, id: false do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :repository, null: false, foreign_key: { on_delete: :cascade }, index: false
    end
    add_index :session_repositories, [ :terminal_session_id, :repository_id ], unique: true
  end
end
