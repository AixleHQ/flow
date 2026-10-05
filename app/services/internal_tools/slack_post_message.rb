# frozen_string_literal: true

module InternalTools
  # Platform tool: let an agent send a Slack message. Text, Block Kit
  # blocks and files are each optional, but at least one is required. Any number
  # of files can be attached, and each one comes from exactly one source:
  #   - content:   inline text the agent typed out (needs filename)
  #   - file_path: a path inside the running container — ANY file type, including
  #                binary (png, pdf, xlsx, ...) the agent just produced this step
  #   - asset_id:  a stored project asset's latest version bytes (any type)
  # Text + files still arrive as ONE message; blocks + files cannot (Slack has no
  # way to attach files to a Block Kit message), so Slack::Notifier posts the
  # message and hangs the files in its thread. Gated on the project having an
  # active Slack integration. Defaults the channel/thread to the message that
  # triggered the run; a session with no Slack trigger behind it must name a
  # channel itself.
  class SlackPostMessage < Base
    include Concerns::SlackContext
    include Concerns::ToolFiles

    tool do
      display_name "Slack Post Message"
      description "Deprecated — use chat_post_message, which works in Slack and Microsoft Teams alike. Send a Slack message. `text`, `blocks` and `files` are all optional but at least one is required. `text` is plain/mrkdwn; `blocks` is Block Kit for rich layout; files can be attached in any number, each entry setting EXACTLY ONE source: `content` (inline text, needs `filename`), `file_path` (a path in the running container — any type incl. binary), or `asset_id` (a project asset's bytes). text + files arrive as one message; blocks + files send the message first and hang the files in its thread. Omit channel/thread to reply in the channel/thread that triggered the run; when nothing Slack-side started this session there is no default, so pass `channel` yourself. Returns the message `ts`, which slack_update_message and slack_delete_message address it by. Requires a Slack integration on the project."
      tags :messaging, :slack
      inject_when :workflow_step_session
      requires_integration :slack
      input_schema({
        type: "object",
        required: [],
        properties: {
          text: {
            type: "string",
            description: "Message text (mrkdwn: *bold*, _italic_, `code`, <https://url|label>). " \
                         "Optional when blocks or files are provided, but keep it set alongside " \
                         "`blocks` — it is the notification and fallback line."
          },
          blocks: {
            type: "array",
            items: { type: "object" },
            description: Concerns::SlackContext::BLOCK_KIT_GUIDE
          },
          files: {
            type: "array",
            items: {
              type: "object",
              required: [],
              properties: {
                title: {
                  type: "string",
                  description: "Optional display title (defaults to filename)"
                },
                filename: {
                  type: "string",
                  description: "File name, e.g. fizzbuzz.rb. Required with `content`; " \
                               "otherwise defaults to the container basename or asset name."
                },
                content: {
                  type: "string",
                  description: "Inline text content of the file. Source option 1 of 3."
                },
                file_path: {
                  type: "string",
                  description: "Path inside the running container to read bytes from, e.g. " \
                               "/workspace/outputs/chart.png. Any file type, including binary. Source option 2 of 3."
                },
                asset_id: {
                  type: "integer",
                  description: "ID of a project asset whose latest-version bytes to attach (any type). Source option 3 of 3."
                }
              }
            },
            description: "Optional file attachments, sent in the SAME message as the text. Each entry sets exactly one of content/file_path/asset_id."
          },
          channel: {
            type: "string",
            description: "Channel ID. Defaults to the triggering channel for Slack-started runs."
          },
          thread_ts: {
            type: "string",
            description: "Thread timestamp to reply into. Defaults to the triggering thread."
          },
          reply_broadcast: {
            type: "boolean",
            description: "Also surface this threaded reply in the channel, for a result everyone " \
                         "should see. Only meaningful when replying in a thread."
          }
        }
      })
    end

    def execute
      files, file_error = build_files
      return file_error if file_error

      blocks, blocks_error = build_blocks
      return blocks_error if blocks_error
      return error("Provide `text`, `blocks` and/or `files`") if params[:text].blank? && blocks.empty? && files.empty?

      integration, channel, target_error = resolve_slack_target(params[:channel])
      return target_error if target_error

      report(channel, Slack::Notifier.post(
        integration: integration, channel: channel, text: params[:text].presence,
        blocks: blocks.presence, files: files.presence,
        thread_ts: params[:thread_ts].presence || slack_context["thread_ts"],
        reply_broadcast: (true if params[:reply_broadcast])
      ))
    end

    private

    # A send that half-landed (the Block Kit message posted, the file upload did
    # not) is reported as a failure that says what DID go out, so the agent retries
    # the missing half instead of the whole message.
    def report(channel, result)
      return error("Failed to send to Slack") if result.nil?
      return error("Partially sent to #{channel}#{ts_suffix(result)} — #{result.error_message}") unless result.ok?

      success("Sent to #{channel}#{ts_suffix(result)}")
    end

    def ts_suffix(result)
      result.ts.present? ? " (ts #{result.ts})" : ""
    end
  end
end
