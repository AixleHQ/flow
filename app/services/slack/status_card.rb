# frozen_string_literal: true

module Slack
  # Chat::StatusCard as a Block Kit message in the thread a request came from,
  # edited there with chat.update. Rate limits are the caller's to retry; any
  # other refusal (the bot left the channel) is logged and dropped.
  module StatusCard
    STATES = {
      "accepted" => [ ":hourglass_flowing_sand:", "Accepted" ],
      "running" => [ ":arrow_forward:", "Running" ],
      "completed" => [ ":white_check_mark:", "Completed" ],
      "failed" => [ ":x:", "Failed" ],
      "cancelled" => [ ":black_square_for_stop:", "Cancelled" ],
      "skipped" => [ ":next_track_button:", "Not started" ]
    }.freeze
    RETRYABLE = %w[ratelimited rate_limited service_unavailable internal_error fatal_error request_timeout].freeze

    module_function

    def post(event, status)
      target = target(event)
      return nil if target.nil?

      token, channel, thread_ts = target
      Slack::Client.post_message(token: token, channel: channel, thread_ts: thread_ts,
                                 text: headline(status), blocks: blocks(status))["ts"]
    rescue Slack::Client::Error => e
      dropped(e)
    end

    def update(event, message_id, status)
      target = target(event)
      return nil if target.nil?

      token, channel, = target
      Slack::Client.update_message(token: token, channel: channel, ts: message_id, text: headline(status),
                                   blocks: blocks(status))
      message_id
    rescue Slack::Client::Error => e
      dropped(e)
    end

    def blocks(status)
      icon, label = STATES.fetch(status.state)
      lines = [ "#{icon} *#{label}* — #{escape(status.workflow)}#{" · run ##{status.run_id}" if status.run_id}" ]
      lines << "Since <!date^#{status.since.to_i}^{time}|#{status.since.utc.strftime('%H:%M UTC')}>" if status.since
      lines << "Took #{status.duration}" if status.duration
      lines << "> #{escape(status.detail.to_s.truncate(400))}" if status.detail.present?
      section = { type: "section", text: { type: "mrkdwn", text: lines.join("\n") } }
      return [ section ] unless status.url

      [ section, { type: "context", elements: [ { type: "mrkdwn", text: "<#{status.url}|Open run>" } ] } ]
    end

    def headline(status)
      "#{STATES.fetch(status.state)[1]}: #{status.workflow}"
    end

    def escape(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    def target(event)
      data = event.data.to_h
      integration = Integration.active.find_by(id: data["integration_id"], provider: :slack)
      token = integration&.credentials_data&.dig("bot_token")
      return nil if token.blank? || data["channel"].blank?

      [ token, data["channel"], data["thread_ts"] || data["ts"] ]
    end

    def dropped(error)
      raise Triggers::ReportToOriginJob::Retryable, error.message if RETRYABLE.include?(error.message)

      Rails.logger.error("[Slack::StatusCard] #{error.message}")
      nil
    end
  end
end
