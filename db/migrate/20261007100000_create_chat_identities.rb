# frozen_string_literal: true

# Who a chat sender is in Aixle, proven by the messenger's own sign-in
# (docs/design/teams-integration.md §9, §20). Not a way to sign in to Aixle.
class CreateChatIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_identities do |t|
      t.string :provider, null: false
      t.string :workspace_id, null: false
      t.string :external_user_id, null: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :proof, null: false
      t.datetime :linked_at, null: false
      t.timestamps
    end
    add_index :chat_identities, %i[provider workspace_id external_user_id], unique: true,
                                                                            name: "index_chat_identities_on_sender"
  end
end
