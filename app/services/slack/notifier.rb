# frozen_string_literal: true

module Slack
  # Outbound Slack messaging using a project install's bot token. Best-effort by
  # design: a missing/inactive integration or a Slack outage is logged and
  # swallowed, never raised into the workflow that triggered the reply.
  class Notifier
    # What a send produced. `ts` is the posted message's timestamp — the handle
    # slack_update_message / slack_delete_message address it by, and the thread
    # parent for anything the agent wants to hang under it.
    #
    # Returned only when SOMETHING reached Slack; `post` answers nil when nothing
    # did, so callers can keep treating the return value as a plain success flag.
    # A send that is half-delivered (the Block Kit message landed, the file upload
    # did not) comes back as a Result carrying `errors` — check `ok?`, not
    # truthiness, when the difference matters.
    Result = Struct.new(:channel, :ts, :thread_ts, :errors, :delivered, keyword_init: true) do
      def ok? = errors.empty?

      def error_message = errors.join("; ")
    end

    class << self
      # Send one Slack message with any mix of text, Block Kit blocks and file
      # attachments. Returns a Result, or nil when nothing was sent at all.
      def post(integration:, channel:, text: nil, files: nil, thread_ts: nil, blocks: nil, reply_broadcast: nil)
        return nil if integration.nil? || channel.blank?
        return nil if text.blank? && files.blank? && blocks.blank?

        token = integration.credentials_data["bot_token"]
        return nil if token.blank?

        deliver(token, Result.new(channel: channel, thread_ts: thread_ts, errors: [], delivered: 0),
          text: text, files: files, blocks: blocks, reply_broadcast: reply_broadcast)
      end

      private

      # Slack has no way to attach files to a Block Kit message, so blocks + files
      # go out as TWO requests: the message first, then the files into that
      # message's own thread, which keeps them together in the channel. Without
      # blocks nothing changes — text and files still ship as one upload.
      def deliver(token, result, text:, files:, blocks:, reply_broadcast:)
        if blocks.present? || files.blank?
          send_chat(token, result, text: text, blocks: blocks, reply_broadcast: reply_broadcast)
        end

        if files.present?
          # Text already carried by the message above would only be repeated here;
          # when that message failed to send, the upload becomes its fallback.
          send_files(token, result, files: files, initial_comment: result.ts ? nil : text)
        end

        result.delivered.zero? ? nil : result
      end

      def send_chat(token, result, text:, blocks:, reply_broadcast:)
        response = Slack::Client.post_message(
          token: token, channel: result.channel, text: text, thread_ts: result.thread_ts,
          blocks: blocks, reply_broadcast: reply_broadcast
        )
        result.ts = response["ts"]
        result.delivered += 1
      rescue Slack::Client::Error => e
        record_failure(result, "message", e)
      end

      def send_files(token, result, files:, initial_comment:)
        Slack::Client.upload_files(
          token: token, channel: result.channel, files: files,
          initial_comment: initial_comment.presence, thread_ts: result.thread_ts || result.ts
        )
        result.delivered += 1
      rescue Slack::Client::Error => e
        record_failure(result, "files", e)
      end

      def record_failure(result, what, error)
        Rails.logger.warn("[Slack::Notifier] #{what} failed: #{error.message}")
        result.errors << "#{what}: #{error.message}"
      end
    end
  end
end
