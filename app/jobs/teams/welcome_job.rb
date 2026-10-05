# frozen_string_literal: true

module Teams
  # One introduction in a conversation the bot was just added to, as Microsoft's
  # guidance asks: in the conversation itself, once, and not in a team so large
  # that a bot announcing itself reads as spam.
  class WelcomeJob < ApplicationJob
    queue_as :default

    LARGE_TEAM = 100

    retry_on Teams::Error, attempts: 3, wait: :polynomially_longer

    def perform(conversation_id)
      conversation = ChatConversation.find_by(id: conversation_id)
      return if conversation.nil? || conversation.welcomed_at || !conversation.installed?

      if conversation.channel? && conversation.team_external_id.present?
        team = Teams::ConnectorClient.team(conversation.teams_reference, conversation.team_external_id)
        conversation.update!(team_aad_group_id: team["aadGroupId"], team_name: team["name"].presence || conversation.team_name)
        ChatConversation.record_team_channels!(
          conversation, Teams::ConnectorClient.channels(conversation.teams_reference, conversation.team_external_id)
        )
        return conversation.update!(welcomed_at: Time.current) if team["memberCount"].to_i > LARGE_TEAM
      end

      Teams::Notifier.post(conversation, text: text(conversation))
      conversation.update!(welcomed_at: Time.current)
    end

    def text(conversation)
      how = conversation.direct? ? "Send me a request" : "Mention me with a request"
      "Hi, I'm Aixle Flow. #{how} and I'll start the workflow it's set up for, then answer in the thread. " \
        "Send `help` to see what can be started from here."
    end
  end
end
