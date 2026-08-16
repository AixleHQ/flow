# frozen_string_literal: true

# Config items attachable to a terminal session, exactly like tools, skills,
# MCP servers, assets and repositories before them.
#
# Attachment is what authorizes `get_config_item` to decrypt a value for that
# session: the tool resolves against the attached set, never against the
# project's items, so a session can only reach what someone deliberately handed
# it. Same id-less join shape as `session_mcp_servers`.
class CreateSessionConfigItems < ActiveRecord::Migration[8.1]
  def change
    create_table :session_config_items, id: false do |t|
      t.bigint :terminal_session_id, null: false
      t.bigint :config_item_id, null: false
    end

    add_index :session_config_items, %i[terminal_session_id config_item_id],
              unique: true, name: "index_session_config_items_on_session_and_item"
    add_index :session_config_items, :config_item_id
  end
end
