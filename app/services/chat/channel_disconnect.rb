# frozen_string_literal: true

module Chat
  # Removes a channel from a company: its triggers there switch off and lose
  # the channel, and the channel is told who left (decision 19 of
  # docs/design/shared-chat-workspaces.md).
  module ChannelDisconnect
    module_function

    def call(conversation, company:)
      connection = ChatChannelConnection.find_by!(chat_conversation: conversation, company_id: company.id)
      ChatChannelConnection.transaction do
        TriggerBinding.release_chat_channels!(
          TriggerBinding.where(chat_conversation_id: conversation.id, project_id: Project.where(company_id: company.id).select(:id))
        )
        connection.destroy!
      end
      AnnounceDisconnectJob.perform_later(conversation.id, company.name)
    end
  end
end
