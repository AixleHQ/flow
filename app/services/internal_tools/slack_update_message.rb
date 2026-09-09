# frozen_string_literal: true

module InternalTools
  # Platform tool: edit a Slack message the bot already posted, addressed by
  # the `ts` slack_post_message returned. What it buys the agent is the
  # "working… → result" pattern: one message in the channel that fills in as the
  # step progresses, instead of a trail of partial updates.
  #
  # chat.update REPLACES the message, so whatever is omitted is dropped from it —
  # a text-only update of a Block Kit message clears its blocks. Files already
  # shared cannot be edited; they are separate uploads.
  class SlackUpdateMessage < Base
    include Concerns::SlackContext

    tool do
      display_name "Slack Update Message"
      description "Edit a Slack message the bot posted, by its `ts` (returned by slack_post_message). Use it for a status message that fills in as the step progresses. The message is REPLACED, not merged: send everything it should end up with — a text-only update of a message that had blocks clears those blocks. Only the bot's own messages can be edited, and already-uploaded files cannot. Omit `channel` only when this session was started from Slack; otherwise name it."
      tags :messaging, :slack
      inject_when :workflow_step_session
      requires_integration :slack
      idempotent
      input_schema({
        type: "object",
        required: %w[ts],
        properties: {
          ts: {
            type: "string",
            description: "Timestamp of the message to edit, e.g. 1700000000.000100. " \
                         "Returned by slack_post_message."
          },
          text: {
            type: "string",
            description: "New message text (mrkdwn). Required unless `blocks` is given; " \
                         "keep it set alongside blocks as the notification and fallback line."
          },
          blocks: {
            type: "array",
            items: { type: "object" },
            description: Concerns::SlackContext::BLOCK_KIT_GUIDE
          },
          channel: {
            type: "string",
            description: "Channel ID the message lives in. Defaults to the triggering channel, when there is one."
          }
        }
      })
    end

    def execute
      blocks, blocks_error = build_blocks
      return blocks_error if blocks_error
      return error("Provide `text` and/or `blocks` to replace the message with") if params[:text].blank? && blocks.empty?

      integration, channel, target_error = resolve_slack_target(params[:channel])
      return target_error if target_error

      _response, call_error = slack_call do
        Slack::Client.update_message(
          token: slack_bot_token(integration), channel: channel, ts: params[:ts].to_s,
          text: params[:text].presence, blocks: blocks.presence
        )
      end
      call_error || success("Updated #{params[:ts]} in #{channel}")
    end
  end
end
