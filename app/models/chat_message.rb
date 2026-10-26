# frozen_string_literal: true

# A message Aixle's bot posted for one company. Every company sharing a
# channel speaks as the same bot, and Slack lets a bot edit any of its own
# messages, so this is what keeps one company's agent off another's
# (docs/design/shared-chat-workspaces.md §11.2).
class ChatMessage < ApplicationRecord
  belongs_to :chat_conversation
  belongs_to :company

  def self.record!(conversation:, message_id:, company_id:)
    return if conversation.nil? || message_id.blank? || company_id.blank?

    insert_all([ { chat_conversation_id: conversation.id, message_id: message_id.to_s, company_id: company_id } ],
               unique_by: %i[chat_conversation_id message_id])
  end

  # In a channel only one company has connected, every bot message there is
  # that company's. Where several have, it must have been posted for this one.
  def self.foreign?(conversation:, message_id:, company_id:)
    return false if conversation.nil? || conversation.chat_channel_connections.count < 2

    !exists?(chat_conversation: conversation, message_id: message_id.to_s, company_id: company_id)
  end
end
