# frozen_string_literal: true

# A chat channel reaches a company only once someone in the channel posted a
# code that company asked for (docs/design/shared-chat-workspaces.md §6, §8), and
# a chat trigger listens to exactly one such channel.
class CreateChatChannelConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_channel_connections do |t|
      t.references :chat_conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.references :requested_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :posted_by_external_id
      t.string :posted_by_name
      t.string :confirmation_message_id
      t.timestamps
    end
    add_index :chat_channel_connections, %i[chat_conversation_id company_id], unique: true

    create_table :chat_connect_codes do |t|
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :trigger_binding, foreign_key: { on_delete: :nullify }
      t.references :requested_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :chat_channel_connection, foreign_key: { on_delete: :nullify }
      t.string :provider, null: false
      t.string :code_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :redeemed_at
      t.string :failure_reason
      t.timestamps
    end
    add_index :chat_connect_codes, :code_digest, unique: true

    add_reference :trigger_bindings, :chat_conversation, foreign_key: { on_delete: :nullify }
  end
end
