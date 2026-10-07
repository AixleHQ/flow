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
      legacy = {
        "channel" => data["channel"],
        # Both, and they differ: `ts` is the message that mentioned us, `thread_ts`
        # the thread it belongs to.
        "ts" => data["ts"],
        "thread_ts" => data["thread_ts"] || data["ts"],
        "team" => data["team"],
        "integration_id" => data["integration_id"],
        "text" => data["raw_text"] || data["text"],
        "user" => data["user"]
      }.compact
      return {} if legacy.empty?

      { "chat" => origin_from_legacy(legacy), "slack" => legacy }
    end

    # The provider-neutral origin (§8.1) of a Slack-started run.
    def origin_from_legacy(slack)
      slack = slack.to_h
      return nil if slack.blank?

      {
        "provider" => KEY,
        "integration_id" => slack["integration_id"],
        "workspace_id" => slack["team"],
        "conversation" => { "id" => slack["channel"], "type" => "channel" }.compact,
        "thread_id" => slack["thread_ts"] || slack["ts"],
        "message_id" => slack["ts"],
        "actor" => { "id" => slack["user"] }.compact,
        "text" => slack["text"]
      }.compact_blank
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

    def scrub_payload(payload) = payload

    def ingest_files(event, project)
      data = event.data.to_h
      integration = TenantScope.owned(Integration, project: project).find_by(id: data["integration_id"])
      return nil if integration.nil?

      Slack::FileIngestor.new(integration: integration, project: project).ingest(data["files"])
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
