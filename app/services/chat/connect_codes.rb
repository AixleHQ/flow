# frozen_string_literal: true

module Chat
  # Issuing and describing connect codes for the trigger form, the integration
  # card, the API and MCP (docs/design/shared-chat-workspaces.md §8.1).
  module ConnectCodes
    Refused = Class.new(StandardError)
    CHANNEL_HINT = {
      "slack" => "its name, such as #deploys",
      "teams" => "Team / Channel, such as Sales / General, or a group chat's name"
    }.freeze

    module_function

    # [record, payload]. The payload carries the code, which is never shown again.
    # With `integration_id`, the code connects a channel only in that install's workspace.
    def issue!(project:, provider:, user:, channel:, trigger_binding: nil, integration_id: nil)
      provider = provider.to_s
      raise Refused, "Unknown messenger #{provider.inspect}" unless Chat::PROVIDERS.key?(provider)
      raise Refused, "Name the channel to connect: #{CHANNEL_HINT.fetch(provider)}" if channel.to_s.delete("#/").squish.blank?

      installs = ChannelAccess.installs(project, provider: provider)
      raise Refused, "Connect #{Chat.provider(provider).label} on the Integrations page first" unless installs.exists?

      integration = installs.find_by(id: integration_id) if integration_id.present?
      if integration_id.present? && integration.nil?
        raise Refused, "No active #{Chat.provider(provider).label} integration #{integration_id} in this project"
      end
      if trigger_binding && !(trigger_binding.chat? && trigger_binding.chat_provider == provider)
        raise Refused, "That trigger does not listen to #{Chat.provider(provider).label}"
      end

      record, code = ChatConnectCode.issue!(project: project, provider: provider, user: user, channel: channel,
                                            trigger_binding: trigger_binding, integration: integration)
      [ record, describe(record, project: project, code: code) ]
    rescue ActiveRecord::RecordInvalid => e
      raise Refused, e.record.errors.full_messages.to_sentence
    end

    # Only issuing may ask Slack for the bot's name; the page polls the rest.
    def describe(record, project:, code: nil)
      bot = Chat.bot_name(record.provider, project, fetch: code.present?, integration: record.integration)
      mention = bot && (record.provider == Chat::SlackProvider::KEY ? "@#{bot}" : bot)
      conversation = record.chat_channel_connection&.chat_conversation
      {
        id: record.id, provider: record.provider, state: record.state, expires_at: record.expires_at.iso8601,
        channel_name: record.channel_label, workspace: record.integration&.chat_workspace_name,
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
