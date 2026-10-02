# frozen_string_literal: true

module Teams
  # The platform's own posts into a conversation the bot knows: help, failure
  # notices, the welcome.
  module Notifier
    module_function

    def post(conversation, text:, thread_id: nil)
      Teams::ConnectorClient.send_message(conversation.teams_reference(thread_id: thread_id),
                                          type: "message", textFormat: "markdown", text: text)
    end

    # Teams markdown reads these as formatting inside a name.
    def escape(value)
      value.to_s.gsub(/([\\*_`~\[\]])/) { "\\#{Regexp.last_match(1)}" }
    end

    def conversation_for(integration_id, external_id)
      return nil if integration_id.blank? || external_id.blank?

      ChatConversation.find_by(integration_id: integration_id, external_id: external_id, provider: "teams")
    end
  end
end
