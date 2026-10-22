# frozen_string_literal: true

# A Slack workspace or Microsoft 365 tenant as a thing of its own, so several
# companies can connect the same one as peers (docs/design/shared-chat-workspaces.md
# §6). The channel registry moves under it, and a company's disconnect no longer
# takes the shared rows with it.
class CreateChatWorkspaces < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_workspaces do |t|
      t.string :provider, null: false
      t.string :external_id, null: false
      t.string :name
      t.string :status, null: false, default: "active"
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :chat_workspaces, %i[provider external_id], unique: true

    add_reference :integrations, :chat_workspace, foreign_key: { on_delete: :nullify }
    add_reference :chat_conversations, :chat_workspace, foreign_key: { on_delete: :cascade }
    add_column :chat_channel_connections, :confirmation_url, :string

    change_column_null :chat_conversations, :integration_id, true
    remove_foreign_key :chat_conversations, :integrations
    add_foreign_key :chat_conversations, :integrations, on_delete: :nullify

    create_table :chat_messages do |t|
      t.references :chat_conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.string :message_id, null: false
      t.timestamps
    end
    add_index :chat_messages, %i[chat_conversation_id message_id], unique: true
  end
end
