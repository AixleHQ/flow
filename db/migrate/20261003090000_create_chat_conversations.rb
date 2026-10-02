# frozen_string_literal: true

# The conversations a chat bot has been added to or addressed in
# (docs/design/teams-integration.md §6.4): where a reply or a proactive post goes,
# and what a trigger form can offer as a channel. Teams ids cannot be typed by
# hand, and a bot can only post where an authenticated activity told it the way.
class CreateChatConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_conversations do |t|
      t.references :integration, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :external_id, null: false
      t.string :kind, null: false
      t.string :name
      t.string :tenant_id
      t.string :team_external_id
      t.string :team_aad_group_id
      t.string :team_name
      t.string :service_url
      t.boolean :installed, null: false, default: true
      t.datetime :welcomed_at
      t.datetime :last_activity_at
      t.timestamps
    end
    add_index :chat_conversations, %i[integration_id external_id], unique: true
  end
end
