# frozen_string_literal: true

module InternalTools
  # Platform tool: read the Slack or Teams thread a run was started from, or
  # another one the bot can see. Without it an agent only ever sees the one
  # message that addressed it.
  class ChatReadThread < Base
    include Concerns::ChatContext
    include Concerns::SlackContext

    DEFAULT_LIMIT = 30
    MAX_LIMIT = 50
    DIRECT_NOTE = "Teams gives an app no access to the history of a 1:1 chat; this is the message that started the run."

    tool do
      display_name "Chat Read Thread"
      description "Read a Slack or Microsoft Teams thread, oldest first. In a run started from chat, call it with no arguments to read the thread behind the request — the usual case. Teams reads channel threads and group chats; in a 1:1 chat Teams lets an app see only the message that started the run. Returns JSON {provider, messages: [...]}. Read a thread once rather than polling it."
      tags :messaging, :chat
      inject_when :workflow_step_session
      requires_integration :chat
      read_only
      input_schema({
        type: "object",
        required: [],
        properties: {
          provider: {
            type: "string", enum: %w[slack teams],
            description: "slack or teams. Defaults to the messenger this run was started from, or the only one connected."
          },
          conversation: {
            type: "string",
            description: "Where: a Slack channel id, or a Teams conversation (\"Team/Channel\", a channel name, or its id). " \
                         "Defaults to the conversation this run was started from."
          },
          thread: {
            type: "string",
            description: "The thread: a Slack thread ts or a Teams thread (root message) id. Defaults to the thread " \
                         "this run was started from, in that conversation."
          },
          limit: { type: "integer", description: "How many of the latest messages, #{DEFAULT_LIMIT} by default, #{MAX_LIMIT} at most." }
        }
      })
    end

    def execute
      provider, provider_error = chat_provider
      return provider_error if provider_error

      provider == "teams" ? read_teams : read_slack
    end

    private

    def limit = (params[:limit].presence&.to_i || DEFAULT_LIMIT).clamp(1, MAX_LIMIT)

    def read_slack
      integration, channel, target_error = resolve_slack_target(params[:conversation])
      return target_error if target_error

      thread = params[:thread].presence || (slack_context["thread_ts"] if channel == slack_context["channel"])
      return error("No thread given, and this run was not started from a thread in that channel") if thread.blank?

      response, call_error = slack_call do
        Slack::Client.conversation_replies(token: slack_bot_token(integration), channel: channel, ts: thread, limit: limit)
      end
      return call_error if call_error

      messages = Array(response["messages"]).map do |m|
        { id: m["ts"], from: m["user"], bot: m["bot_id"].present?, text: m["text"],
          files: Array(m["files"]).filter_map { |f| f["name"] }.presence }.compact
      end
      success({ provider: "slack", conversation: channel, thread: thread, messages: messages,
                has_more: response["has_more"].present? }.to_json)
    end

    def read_teams
      conversation, target_error = teams_target
      return target_error if target_error
      return success({ provider: "teams", messages: [ origin_message ].compact, note: DIRECT_NOTE }.to_json) if conversation.direct?

      thread = teams_thread(conversation)
      return error("Name the `thread` to read in this channel") if conversation.channel? && thread.blank?

      messages = Teams::Messages.read_thread(conversation, thread_id: thread, limit: limit)
      success({ provider: "teams", conversation: conversation.external_id, thread: thread, messages: messages }.compact.to_json)
    rescue Teams::Error => e
      teams_failure(e)
    end

    def origin_message
      origin = chat_origin
      return nil unless origin["provider"] == "teams"

      { id: origin["message_id"], from: origin.dig("actor", "name"), text: origin["text"] }.compact
    end
  end
end
