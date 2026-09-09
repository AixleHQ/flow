# frozen_string_literal: true

module InternalTools
  # Platform tool: read the thread a run was started from (or any other thread in
  # a channel the bot is in). Without it an agent only ever sees the single
  # @mention that triggered it, and has no way to pick up the conversation that
  # led to the ask.
  #
  # Needs a history scope for the conversation kind. The app requests
  # channels:history and groups:history, so public and private channels work;
  # DM threads (im:history / mpim:history) do not. Slack rate-limits
  # conversations.replies hard for newer non-Marketplace apps — this is a tool for
  # reading a thread once, not for polling it.
  class SlackReadThread < Base
    include Concerns::SlackContext

    DEFAULT_LIMIT = 50
    MAX_LIMIT = 200

    tool do
      display_name "Slack Read Thread"
      description "Read a Slack thread: the parent message and its replies, oldest first. In a run triggered from Slack, call it with no arguments to read the thread behind the request — the usual case; anywhere else, name `channel` and `thread_ts`. Returns JSON: {messages: [{ts, user, bot_id, text, files}], has_more, next_cursor}. Public and private channels only (not DMs). Read a thread once rather than polling it."
      tags :messaging, :slack
      inject_when :workflow_step_session
      requires_integration :slack
      read_only
      input_schema({
        type: "object",
        required: [],
        properties: {
          thread_ts: {
            type: "string",
            description: "Timestamp of the thread's parent message. Defaults to the thread that " \
                         "triggered this run."
          },
          channel: {
            type: "string",
            description: "Channel ID the thread lives in. Defaults to the triggering channel, when there is one."
          },
          limit: {
            type: "integer",
            description: "How many messages to return, #{DEFAULT_LIMIT} by default, #{MAX_LIMIT} at most."
          },
          cursor: {
            type: "string",
            description: "Pagination cursor — pass the `next_cursor` from a previous call."
          }
        }
      })
    end

    def execute
      integration, channel, target_error = resolve_slack_target(params[:channel])
      return target_error if target_error

      thread_ts = params[:thread_ts].presence || slack_context["thread_ts"].presence
      return error("No thread given, and this run was not triggered from a Slack thread") if thread_ts.blank?

      response, call_error = slack_call do
        Slack::Client.conversation_replies(
          token: slack_bot_token(integration), channel: channel, ts: thread_ts,
          limit: limit, cursor: params[:cursor].presence
        )
      end
      call_error || success(render(response))
    end

    private

    def limit
      value = params[:limit].presence&.to_i || DEFAULT_LIMIT
      value.clamp(1, MAX_LIMIT)
    end

    def render(response)
      {
        messages: Array(response["messages"]).map { |m| message_fields(m) },
        has_more: response["has_more"].present?,
        next_cursor: response.dig("response_metadata", "next_cursor").presence
      }.compact.to_json
    end

    # The fields an agent can act on. `bot_id` is what distinguishes our own
    # earlier replies in the thread from what a human said.
    def message_fields(message)
      {
        ts: message["ts"],
        user: message["user"],
        bot_id: message["bot_id"],
        text: message["text"],
        files: Array(message["files"]).filter_map { |f| f["name"] }.presence
      }.compact
    end
  end
end
