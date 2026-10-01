# frozen_string_literal: true

module Webhooks
  # Async second half of inbound webhook handling: take a stored ReceivedWebhook,
  # normalize the provider payload into a CloudEvents-style TriggerEvent, and
  # publish it so the TriggerEngine matches it against TriggerBinding rules.
  class ProcessEventJob < ApplicationJob
    queue_as :default

    # Slack sends message text in its own markup: these three characters arrive
    # as entities, and a mention as <@U…> or <@U…|name>.
    SLACK_ENTITIES = { "&amp;" => "&", "&lt;" => "<", "&gt;" => ">" }.freeze

    def perform(received_webhook_id)
      received = ReceivedWebhook.find_by(id: received_webhook_id)
      return if received.nil? || received.status == "processed"

      endpoint = received.webhook_endpoint
      normalized = normalize(endpoint, received.raw_payload)

      if normalized.nil?
        received.update!(status: "skipped")
        return
      end

      # Slack endpoints are company-scoped (one workspace serves every project of
      # the company) → company-wide fan-out. Other endpoints stay project-scoped.
      TriggerEngine.publish(
        event_type: normalized[:event_type],
        source: "#{endpoint.provider}:#{endpoint.slug}",
        subject: normalized[:subject],
        data: normalized[:data],
        project: endpoint.project,
        company: endpoint.company,
        dedup_key: "#{endpoint.provider}:#{received.idempotency_key}"
      )

      received.update!(status: "processed")
    end

    private

    # Provider-specific payload → normalized event. Returns nil to skip.
    def normalize(endpoint, payload)
      case endpoint.provider.to_s
      when "slack"   then normalize_slack(endpoint, payload)
      else                normalize_generic(endpoint, payload)
      end
    end

    def normalize_slack(endpoint, payload)
      event = payload["event"]
      return nil unless event.is_a?(Hash)

      kind = event["type"].to_s # "message", "app_mention", "reaction_added", ...
      # Mention-based ChatOps: only act when the bot is explicitly @mentioned. Slack
      # delivers that as an `app_mention` event. Every other channel message arrives
      # as a plain `message` event — ignore it, so the bot only responds when called
      # (and a mention doesn't double-fire: the same message is ALSO sent as
      # `message`, which we drop here).
      return nil unless kind == "app_mention"
      return nil if event["bot_id"].present? # safety: ignore bot-authored mentions

      integration_id = endpoint.config.to_h["integration_id"]
      {
        event_type: "slack.message",
        subject: event["channel"],
        data: {
          "slack_event_type" => kind,
          "channel" => event["channel"],
          "user" => event["user"],
          # What trigger conditions match: the request as the person typed it.
          # raw_text is Slack's own text, which is what the run is handed.
          "text" => slack_request_text(event["text"], slack_bot_user_id(integration_id)),
          "raw_text" => event["text"],
          "team" => payload["team_id"],
          # Reply coordinates + attachments, carried into the run via shared_context
          # (replies) and File ingestion (input assets).
          "ts" => event["ts"],
          "thread_ts" => event["thread_ts"].presence || event["ts"],
          "files" => normalize_slack_files(event["files"]),
          "integration_id" => integration_id
        }.compact
      }
    end

    # "<@UBOT> Deploy &amp; tag" → "Deploy & tag": the leading mention of the
    # bot dropped, entities decoded, whitespace trimmed. When the install can't
    # say who the bot is, any leading mention is dropped.
    def slack_request_text(text, bot_user_id)
      return nil if text.nil?

      id = bot_user_id.present? ? Regexp.escape(bot_user_id) : "[A-Z0-9]+"
      text.sub(/\A\s*<@#{id}(?:\|[^>]*)?>/, "").gsub(/&(?:amp|lt|gt);/, SLACK_ENTITIES).strip
    end

    def slack_bot_user_id(integration_id)
      return nil if integration_id.blank?

      Integration.find_by(id: integration_id)&.credentials_data_for_display&.dig("bot_user_id")
    end

    # Keep only the file fields we need (and only well-formed entries); nil when
    # the message has no attachments so the key drops out of the event data.
    def normalize_slack_files(files)
      Array(files).filter_map do |f|
        next unless f.is_a?(Hash)

        f.slice("id", "name", "title", "url_private", "url_private_download", "mimetype", "filetype", "size")
      end.presence
    end

    def normalize_generic(endpoint, payload)
      {
        event_type: endpoint.config["event_type"].presence || "webhook.received",
        subject: nil,
        data: payload.is_a?(Hash) ? payload : { "body" => payload }
      }
    end
  end
end
