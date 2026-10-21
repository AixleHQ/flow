# frozen_string_literal: true

module Chat
  # Issuing and describing connect codes for the trigger form, the integration
  # card, the API and MCP (docs/design/shared-chat-workspaces.md §8.1).
  module ConnectCodes
    Refused = Class.new(StandardError)

    module_function

    # [record, payload]. The payload carries the code, which is never shown again.
    def issue!(project:, provider:, user:, trigger_binding: nil)
      provider = provider.to_s
      raise Refused, "Unknown messenger #{provider.inspect}" unless Chat::PROVIDERS.key?(provider)
      unless Integration.active.visible_for_project(project).exists?(provider: provider)
        raise Refused, "Connect #{Chat.provider(provider).label} on the Integrations page first"
      end
      if trigger_binding && !(trigger_binding.chat? && trigger_binding.chat_provider == provider)
        raise Refused, "That trigger does not listen to #{Chat.provider(provider).label}"
      end

      record, code = ChatConnectCode.issue!(project: project, provider: provider, user: user, trigger_binding: trigger_binding)
      [ record, describe(record, project: project, code: code) ]
    rescue ActiveRecord::RecordInvalid => e
      raise Refused, e.record.errors.full_messages.to_sentence
    end

    # Only issuing may ask Slack for the bot's name; the page polls the rest.
    def describe(record, project:, code: nil)
      bot = Chat.bot_name(record.provider, project, fetch: code.present?)
      mention = bot && (record.provider == Chat::SlackProvider::KEY ? "@#{bot}" : bot)
      conversation = record.chat_channel_connection&.chat_conversation
      {
        id: record.id, provider: record.provider, state: record.state, expires_at: record.expires_at.iso8601,
        trigger_id: record.trigger_binding_id, failure_reason: record.failure_reason,
        bot_name: bot, mention: mention, invite: invite(record.provider, mention),
        command: code && "connect #{code}", code: code,
        channel: conversation && ChannelAccess.describe(conversation)
      }.compact
    end

    def invite(provider, mention)
      if provider == Chat::SlackProvider::KEY
        "/invite #{mention || '@<bot name>'}"
      else
        "Add #{mention || 'the Aixle Flow app'} to the team or group chat"
      end
    end
  end
end
