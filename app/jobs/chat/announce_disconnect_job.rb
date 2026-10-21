# frozen_string_literal: true

module Chat
  # Tells a channel a company disconnected it, so the trace the connection left
  # there stays complete. Best-effort: a channel the bot was removed from
  # simply gets nothing.
  class AnnounceDisconnectJob < ApplicationJob
    queue_as :default

    def perform(conversation_id, company_name)
      conversation = ChatConversation.find_by(id: conversation_id)
      return if conversation.nil? || !conversation.integration&.active?

      provider = Chat.provider(conversation.provider)
      text = "#{provider.strong(company_name)} disconnected this channel."
      if conversation.provider == Chat::SlackProvider::KEY
        Slack::Notifier.post(integration: conversation.integration, channel: conversation.external_id, text: text)
      else
        Teams::Notifier.post(conversation, text: text)
      end
    rescue Teams::Error => e
      Rails.logger.warn("[Chat::AnnounceDisconnectJob] conversation ##{conversation_id}: #{e.message}")
    end
  end
end
