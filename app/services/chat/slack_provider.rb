# frozen_string_literal: true

module Chat
  # Slack behind the messaging port: its Events API payload in, the `chat.message`
  # contract out (docs/design/teams-integration.md §7.3), and the existing Slack
  # services for everything said back.
  module SlackProvider
    KEY = "slack"
    LABEL = "Slack"

    # Slack sends message text in its own markup: these three characters arrive
    # as entities, and a mention as <@U…> or <@U…|name>.
    ENTITIES = { "&amp;" => "&", "&lt;" => "<", "&gt;" => ">" }.freeze
    MENTION = /<@[A-Z0-9]+>/i
    HELP_COMMAND = %r{\A/help\z}i

    module_function

    def key = KEY
    def label = LABEL

    def normalize(endpoint, payload)
      event = payload["event"]
      return nil unless event.is_a?(Hash)

      kind = event["type"].to_s
      # The same mention also arrives as a plain `message` event; acting on
      # `app_mention` alone answers each mention once and ignores everything else.
      return nil unless kind == "app_mention"
      return nil if event["bot_id"].present?

      integration_id = endpoint.config.to_h["integration_id"]
      thread_ts = event["thread_ts"].presence || event["ts"]
      {
        event_type: Chat::EVENT_TYPE,
        subject: event["channel"],
        data: {
          "provider" => KEY,
          "workspace" => { "id" => payload["team_id"] }.compact.presence,
          "conversation" => { "id" => event["channel"], "type" => "channel" }.compact,
          "thread_id" => thread_ts,
          "message_id" => event["ts"],
          "actor" => { "id" => event["user"] }.compact.presence,
          "slack_event_type" => kind,
          "channel" => event["channel"],
          "user" => event["user"],
          # Trigger conditions match the request as the person typed it; the run
          # is handed Slack's own text.
          "text" => request_text(event["text"], bot_user_id(integration_id)),
          "raw_text" => event["text"],
          "team" => payload["team_id"],
          "ts" => event["ts"],
          "thread_ts" => thread_ts,
          "files" => normalize_files(event["files"]),
          "integration_id" => integration_id
        }.compact
      }
    end

    def help_request?(event)
      event.data.to_h["text"].to_s.gsub(MENTION, "").strip.match?(HELP_COMMAND)
    end

    def answer_help(event)
      Slack::HelpResponder.call(event)
    end

    def report_failure(run)
      Slack::RunFailureNotifier.call(run)
    end

    def post_status_card(event, status) = Slack::StatusCard.post(event, status)

    def update_status_card(event, message_id, status) = Slack::StatusCard.update(event, message_id, status)

    def run_context(event)
      data = event.data.to_h
      { "chat" => data.slice("provider", "integration_id", "conversation", "thread_id", "message_id", "actor")
                      .merge("workspace_id" => data.dig("workspace", "id"), "text" => data["raw_text"] || data["text"])
                      .compact_blank }
    end

    # How a reply names the person who sent the message.
    def mention(actor)
      id = actor.to_h["id"]
      id.present? ? "<@#{id}>" : nil
    end

    # Each project a company-wide message fans out to gets its own copy of the
    # files, through an install of that project's company. Nil when there is no
    # such install, so the caller falls back to whatever the event already names.
    def scrub(data) = data

    def private_request?(_event) = false

    def answer_private(_event) = false

    def answer_command(_event) = false

    def scrub_payload(payload) = payload

    def ingest_files(event, project)
      data = event.data.to_h
      integration = TenantScope.owned(Integration, project: project).find_by(id: data["integration_id"])
      return nil if integration.nil?

      Slack::FileIngestor.new(integration: integration, project: project).ingest(data["files"])
    end

    # The connect flow's answer, in the thread it was asked in. The posted
    # message's ts, or nil when nothing reached Slack.
    def reply(event, text)
      data = event.data.to_h
      Slack::Notifier.post(integration: install_for(event), channel: data["channel"], text: text,
                           thread_ts: data["thread_ts"].presence || data["ts"])&.ts
    end

    def permalink(event, message_id)
      integration = install_for(event)
      return nil if integration.nil? || message_id.blank?

      Slack::Client.permalink(token: integration.credentials_data["bot_token"], channel: event.data.to_h["channel"],
                              message_ts: message_id)["permalink"]
    rescue Slack::Client::Error
      nil
    end

    # Only the person who posted sees it.
    def reply_privately(event, text)
      data = event.data.to_h
      integration = install_for(event)
      return nil if integration.nil? || data["user"].blank?

      Slack::Client.post_ephemeral(token: integration.credentials_data["bot_token"], channel: data["channel"],
                                   user: data["user"], text: text, thread_ts: data["thread_ts"].presence || data["ts"])
    rescue Slack::Client::Error => e
      Rails.logger.warn("[Chat::SlackProvider] private reply failed: #{e.message}")
      nil
    end

    def strong(text) = "*#{escape(text)}*"

    # Slack mrkdwn reads these three characters as markup.
    def escape(text) = text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

    def bot_mention(event)
      id = bot_user_id(event.data.to_h["integration_id"])
      id.present? ? "<@#{id}>" : "the bot"
    end

    # Slack keeps no registry of its channels here, so the row is written when a
    # channel is connected, with the name Slack gives it when the install may read it.
    def conversation_for(event, integration)
      channel = event.data.to_h["channel"].to_s
      return nil if channel.blank?

      ChatConversation.record_slack!(integration: integration, channel_id: channel, name: channel_name(integration, channel))
    end

    # Slack completes a mention from the display name only, never from the
    # username auth.test returns, so instructions name the bot by its display
    # name and fall back to the username while users:read is missing.
    def bot_name(token)
      me = Slack::Client.auth_test(token: token)
      display_name(token, me["user_id"]) || me["user"].presence
    rescue Slack::Client::Error
      nil
    end

    def person_name(integration, actor)
      display_name(integration.credentials_data["bot_token"], actor.to_h["id"])
    end

    def display_name(token, user_id)
      return nil if user_id.blank?

      profile = Slack::Client.user_info(token: token, user: user_id).dig("user", "profile").to_h
      profile["display_name"].presence || profile["real_name"].presence
    rescue Slack::Client::Error => e
      Rails.logger.info("[Chat::SlackProvider] no name for #{user_id}: #{e.message}")
      nil
    end

    def channel_name(integration, channel)
      Slack::Client.conversation_info(token: integration.credentials_data["bot_token"], channel: channel).dig("channel", "name")
    rescue Slack::Client::Error => e
      Rails.logger.info("[Chat::SlackProvider] no name for #{channel}: #{e.message}")
      nil
    end

    def install_for(event)
      data = event.data.to_h
      Slack::InstallResolver.call(company_id: event.company_id || event.project&.company_id, project_id: event.project_id,
                                  integration_id: data["integration_id"], team_id: data["team"])
    end

    # "<@UBOT> Deploy &amp; tag" → "Deploy & tag": the leading mention of the bot
    # dropped, entities decoded, whitespace trimmed. When the install can't say
    # who the bot is, any leading mention is dropped.
    def request_text(text, bot_user_id)
      return nil if text.nil?

      id = bot_user_id.present? ? Regexp.escape(bot_user_id) : "[A-Z0-9]+"
      text.sub(/\A\s*<@#{id}(?:\|[^>]*)?>/, "").gsub(/&(?:amp|lt|gt);/, ENTITIES).strip
    end

    def bot_user_id(integration_id)
      return nil if integration_id.blank?

      Integration.find_by(id: integration_id)&.credentials_data_for_display&.dig("bot_user_id")
    end

    def normalize_files(files)
      Array(files).filter_map do |f|
        next unless f.is_a?(Hash)

        f.slice("id", "name", "title", "url_private", "url_private_download", "mimetype", "filetype", "size")
      end.presence
    end
  end
end
