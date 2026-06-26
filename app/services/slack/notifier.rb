# frozen_string_literal: true

module Slack
  # Outbound Slack messaging using a project install's bot token. Best-effort by
  # design: a missing/inactive integration or a Slack outage is logged and
  # swallowed, never raised into the workflow that triggered the reply.
  class Notifier
    class << self
      # Send one Slack message with optional text and/or file attachments. When
      # files are present they're uploaded and shared together with `text` as a
      # single message; otherwise a plain chat.postMessage is sent.
      def post(integration:, channel:, text: nil, files: nil, thread_ts: nil, blocks: nil)
        return false if integration.nil? || channel.blank?
        return false if text.blank? && files.blank?

        token = integration.credentials_data["bot_token"]
        return false if token.blank?

        if files.present?
          Slack::Client.upload_files(token: token, channel: channel, files: files,
            initial_comment: text, thread_ts: thread_ts)
        else
          Slack::Client.post_message(token: token, channel: channel, text: text, thread_ts: thread_ts, blocks: blocks)
        end
        true
      rescue Slack::Client::Error => e
        Rails.logger.warn("[Slack::Notifier] post failed: #{e.message}")
        false
      end

      # Reply into the Slack thread that started a run (no-op for non-Slack runs).
      def notify_run(run, text)
        slack = run.shared_context.to_h["slack"]
        return false if slack.blank?

        integration = Integration.find_by(id: slack["integration_id"])
        post(integration: integration, channel: slack["channel"], text: text, thread_ts: slack["thread_ts"])
      end
    end
  end
end
