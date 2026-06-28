# frozen_string_literal: true

module Webhooks
  # Async second half of inbound webhook handling: take a stored ReceivedWebhook,
  # normalize the provider payload into a CloudEvents-style TriggerEvent, and
  # publish it so the TriggerEngine matches it against TriggerBinding rules.
  class ProcessEventJob < ApplicationJob
    queue_as :default

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

      {
        event_type: "slack.message",
        subject: event["channel"],
        data: {
          "slack_event_type" => kind,
          "channel" => event["channel"],
          "user" => event["user"],
          "text" => event["text"],
          "team" => payload["team_id"],
          # Reply coordinates + attachments, carried into the run via shared_context
          # (replies) and File ingestion (input assets).
          "ts" => event["ts"],
          "thread_ts" => event["thread_ts"].presence || event["ts"],
          "files" => normalize_slack_files(event["files"]),
          "integration_id" => endpoint.config.to_h["integration_id"]
        }.compact
      }
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
